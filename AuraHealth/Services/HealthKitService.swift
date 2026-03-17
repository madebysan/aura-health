import Foundation
import SwiftData
import HealthKit
import os

private let logger = Logger(subsystem: "com.santiagoalonso.aurahealth", category: "HealthKit")

/// Apple Health (HealthKit) integration
@Observable
@MainActor
final class HealthKitService {
    var isAuthorized = false
    var isSyncing = false
    var lastSyncDate: Date?
    var error: String?
    var syncProgress: SyncProgress?

    struct SyncProgress {
        var imported: Int = 0
        var phase: String = ""
    }

    private let healthStore = HKHealthStore()

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    init() {
        if let lastSync = UserDefaults.standard.object(forKey: "healthkit-last-sync") as? Date {
            self.lastSyncDate = lastSync
        }
        // Check if we've previously authorized
        if isAvailable && UserDefaults.standard.bool(forKey: "healthkit-authorized") {
            isAuthorized = true
        }
    }

    // Types we want to read
    private var readTypes: Set<HKObjectType> {
        Set([
            HKQuantityType(.stepCount),
            HKQuantityType(.heartRate),
            HKQuantityType(.bodyMass),
            HKQuantityType(.bloodPressureSystolic),
            HKQuantityType(.bloodPressureDiastolic),
            HKQuantityType(.oxygenSaturation),
            HKQuantityType(.bodyTemperature),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.appleExerciseTime),
            HKCategoryType(.sleepAnalysis),
        ].compactMap { $0 })
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        guard isAvailable else {
            error = "HealthKit is not available on this device"
            return
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
            isAuthorized = true
            UserDefaults.standard.set(true, forKey: "healthkit-authorized")
            error = nil
        } catch {
            self.error = "Authorization failed: \(error.localizedDescription)"
        }
    }

    func disconnect() {
        // Can't revoke HealthKit access programmatically — user must do it in Settings/Health app
        // But we can stop syncing and clear our state
        isAuthorized = false
        lastSyncDate = nil
        UserDefaults.standard.removeObject(forKey: "healthkit-authorized")
        UserDefaults.standard.removeObject(forKey: "healthkit-last-sync")
        error = nil
    }

    // MARK: - Sync

    /// Pre-fetched lookup of existing measurements to avoid N+1 queries during import
    private var existingMeasurements: Set<String> = []

    private func buildExistingLookup(context: ModelContext, since startDate: Date) {
        let descriptor = FetchDescriptor<Measurement>(
            predicate: #Predicate { $0.timestamp >= startDate }
        )
        let all = (try? context.fetch(descriptor)) ?? []
        existingMeasurements = Set(all.map { measurement in
            let day = Calendar.current.startOfDay(for: measurement.timestamp)
            return "\(measurement.metricType.rawValue)-\(measurement.source.rawValue)-\(day.timeIntervalSince1970)"
        })
    }

    func syncData(into context: ModelContext, days: Int = 30) async {
        if !isAuthorized {
            await requestAuthorization()
            guard isAuthorized else { return }
        }

        isSyncing = true
        error = nil
        syncProgress = SyncProgress()

        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        // Build lookup once instead of querying per-item
        buildExistingLookup(context: context, since: startDate)

        logger.notice("[HealthKit] Starting sync, \(days) days back from \(startDate.formatted())")

        do {
            syncProgress?.phase = "Steps"
            try await syncDailySum(.stepCount, metricType: .steps, unit: .count(), context: context, since: startDate)

            syncProgress?.phase = "Heart Rate"
            try await syncQuantity(.heartRate, metricType: .heartRate, unit: .count().unitDivided(by: .minute()), context: context, since: startDate)

            syncProgress?.phase = "Weight"
            // Weight is sparse — sync a full year and allow updates to existing values
            let weightStart = Calendar.current.date(byAdding: .day, value: -365, to: Date())!
            try await syncWeight(context: context, since: weightStart)

            syncProgress?.phase = "Blood Oxygen"
            try await syncQuantity(.oxygenSaturation, metricType: .spo2, unit: .percent(), context: context, since: startDate, multiplier: 100)

            syncProgress?.phase = "Temperature"
            try await syncQuantity(.bodyTemperature, metricType: .skinTemp, unit: .degreeCelsius(), context: context, since: startDate)

            syncProgress?.phase = "Calories"
            try await syncDailySum(.activeEnergyBurned, metricType: .calories, unit: .kilocalorie(), context: context, since: startDate)

            syncProgress?.phase = "HRV"
            try await syncQuantity(.heartRateVariabilitySDNN, metricType: .hrv, unit: .secondUnit(with: .milli), context: context, since: startDate)

            syncProgress?.phase = "Exercise"
            try await syncDailySum(.appleExerciseTime, metricType: .activeMinutes, unit: .minute(), context: context, since: startDate)

            syncProgress?.phase = "Blood Pressure"
            try await syncBloodPressure(context: context, since: startDate)

            syncProgress?.phase = "Sleep"
            try await syncSleep(context: context, since: startDate)

            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: "healthkit-last-sync")
            logger.notice("[HealthKit] Sync complete. Total imported: \(self.syncProgress?.imported ?? 0)")
        } catch {
            logger.error("[HealthKit] Sync failed: \(error.localizedDescription)")
            self.error = "Sync failed: \(error.localizedDescription)"
        }

        existingMeasurements.removeAll()
        syncProgress = nil
        isSyncing = false
    }

    // MARK: - Query Helpers

    /// Sync individual samples (heart rate, weight, etc.) — takes the latest per day
    private func syncQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        metricType: MetricType,
        unit: HKUnit,
        context: ModelContext,
        since startDate: Date,
        multiplier: Double = 1
    ) async throws {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            logger.warning("[HealthKit] \(metricType.displayName): type not available")
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1000
        )

        let samples = try await descriptor.result(for: healthStore)

        // Group by day, take the latest sample per day
        let cal = Calendar.current
        let grouped = Dictionary(grouping: samples) { cal.startOfDay(for: $0.startDate) }

        var inserted = 0
        for (day, daySamples) in grouped {
            guard let latest = daySamples.first else { continue }
            let value = latest.quantity.doubleValue(for: unit) * multiplier
            if insertIfNew(context: context, timestamp: day, type: metricType, value: value) {
                syncProgress?.imported += 1
                inserted += 1
            }
        }
        logger.notice("[HealthKit] \(metricType.displayName): \(samples.count) samples → \(grouped.count) days → \(inserted) new")
    }

    /// Dedicated weight sync — fetches all samples over a long window, takes the latest per day,
    /// and upserts (updates stale values) so the chart reflects actual changes over time.
    private func syncWeight(context: ModelContext, since startDate: Date) async throws {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return }
        let unit = HKUnit.gramUnit(with: .kilo)

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 5000
        )

        let samples = try await descriptor.result(for: healthStore)

        // Group by day, take the latest sample per day
        let cal = Calendar.current
        let grouped = Dictionary(grouping: samples) { cal.startOfDay(for: $0.startDate) }

        // Fetch existing weight measurements for upsert
        let weightType = MetricType.weight
        let healthSource = MeasurementSource.appleHealth
        let existingDescriptor = FetchDescriptor<Measurement>(
            predicate: #Predicate { $0.metricType == weightType && $0.source == healthSource && $0.timestamp >= startDate }
        )
        let existingWeights = (try? context.fetch(existingDescriptor)) ?? []
        let existingByDay = Dictionary(grouping: existingWeights) { cal.startOfDay(for: $0.timestamp) }

        var inserted = 0
        var updated = 0
        for (day, daySamples) in grouped {
            guard let latest = daySamples.first else { continue }
            let value = latest.quantity.doubleValue(for: unit)

            if let existing = existingByDay[day]?.first {
                // Update if value changed (more than 0.05 kg difference)
                if abs(existing.value - value) > 0.05 {
                    existing.value = value
                    updated += 1
                }
            } else {
                let key = "\(MetricType.weight.rawValue)-\(MeasurementSource.appleHealth.rawValue)-\(day.timeIntervalSince1970)"
                if !existingMeasurements.contains(key) {
                    existingMeasurements.insert(key)
                    context.insert(Measurement(timestamp: day, metricType: .weight, value: value, source: .appleHealth))
                    syncProgress?.imported += 1
                    inserted += 1
                }
            }
        }
        logger.notice("[HealthKit] Weight: \(samples.count) samples → \(grouped.count) days → \(inserted) new, \(updated) updated")
    }

    /// Sync cumulative metrics (steps, calories, exercise minutes) — sums per day
    private func syncDailySum(
        _ identifier: HKQuantityTypeIdentifier,
        metricType: MetricType,
        unit: HKUnit,
        context: ModelContext,
        since startDate: Date
    ) async throws {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            logger.warning("[HealthKit] \(metricType.displayName): type not available")
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: 5000
        )

        let samples = try await descriptor.result(for: healthStore)

        // Sum by day
        let cal = Calendar.current
        let grouped = Dictionary(grouping: samples) { cal.startOfDay(for: $0.startDate) }

        var inserted = 0
        for (day, daySamples) in grouped {
            let total = daySamples.reduce(0.0) { $0 + $1.quantity.doubleValue(for: unit) }
            if total > 0 {
                if insertIfNew(context: context, timestamp: day, type: metricType, value: total) {
                    syncProgress?.imported += 1
                    inserted += 1
                }
            }
        }
        logger.notice("[HealthKit] \(metricType.displayName): \(samples.count) samples → \(grouped.count) days → \(inserted) new")
    }

    private func syncBloodPressure(context: ModelContext, since startDate: Date) async throws {
        guard let systolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic),
              let diastolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic) else { return }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let mmHg = HKUnit.millimeterOfMercury()

        let sysDescriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: systolicType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 500
        )

        let diasDescriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: diastolicType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 500
        )

        let systolicSamples = try await sysDescriptor.result(for: healthStore)
        let diastolicSamples = try await diasDescriptor.result(for: healthStore)

        // Match by timestamp
        let diastolicByDate = Dictionary(grouping: diastolicSamples) { $0.startDate }

        for sys in systolicSamples {
            let sysValue = sys.quantity.doubleValue(for: mmHg)
            let diaValue = diastolicByDate[sys.startDate]?.first?.quantity.doubleValue(for: mmHg)

            let day = Calendar.current.startOfDay(for: sys.startDate)
            let key = "\(MetricType.bloodPressure.rawValue)-\(MeasurementSource.appleHealth.rawValue)-\(day.timeIntervalSince1970)"

            if !existingMeasurements.contains(key) {
                existingMeasurements.insert(key)
                context.insert(Measurement(
                    timestamp: sys.startDate,
                    metricType: .bloodPressure,
                    value: sysValue,
                    value2: diaValue,
                    source: .appleHealth
                ))
                syncProgress?.imported += 1
            }
        }
    }

    private func syncSleep(context: ModelContext, since startDate: Date) async throws {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 500
        )

        let samples = try await descriptor.result(for: healthStore)

        // Group by night (start date's day)
        let grouped = Dictionary(grouping: samples) { Calendar.current.startOfDay(for: $0.startDate) }

        for (night, nightSamples) in grouped {
            let totalSleep = nightSamples.reduce(0.0) { total, sample in
                if sample.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue
                    || sample.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue
                    || sample.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
                    || sample.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue {
                    return total + sample.endDate.timeIntervalSince(sample.startDate) / 3600
                }
                return total
            }

            if totalSleep > 0 {
                if insertIfNew(context: context, timestamp: night, type: .sleepDuration, value: totalSleep) {
                    syncProgress?.imported += 1
                }
            }
        }
    }

    @discardableResult
    private func insertIfNew(context: ModelContext, timestamp: Date, type: MetricType, value: Double) -> Bool {
        let day = Calendar.current.startOfDay(for: timestamp)
        let key = "\(type.rawValue)-\(MeasurementSource.appleHealth.rawValue)-\(day.timeIntervalSince1970)"

        if existingMeasurements.contains(key) {
            return false
        }

        existingMeasurements.insert(key)
        context.insert(Measurement(timestamp: timestamp, metricType: type, value: value, source: .appleHealth))
        return true
    }
}
