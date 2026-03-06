import Foundation
import SwiftData
import HealthKit

/// Apple Health (HealthKit) integration
@Observable
@MainActor
final class HealthKitService {
    var isAuthorized = false
    var isSyncing = false
    var lastSyncDate: Date?
    var error: String?

    private let healthStore = HKHealthStore()

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
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
            error = nil
        } catch {
            self.error = "Authorization failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Sync

    func syncData(into context: ModelContext, days: Int = 30) async {
        if !isAuthorized {
            await requestAuthorization()
            guard isAuthorized else { return }
        }

        isSyncing = true
        error = nil

        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        do {
            try await syncQuantity(.stepCount, metricType: .steps, unit: .count(), context: context, since: startDate)
            try await syncQuantity(.heartRate, metricType: .heartRate, unit: .count().unitDivided(by: .minute()), context: context, since: startDate)
            try await syncQuantity(.bodyMass, metricType: .weight, unit: .gramUnit(with: .kilo), context: context, since: startDate)
            try await syncQuantity(.oxygenSaturation, metricType: .spo2, unit: .percent(), context: context, since: startDate, multiplier: 100)
            try await syncQuantity(.bodyTemperature, metricType: .skinTemp, unit: .degreeCelsius(), context: context, since: startDate)
            try await syncQuantity(.activeEnergyBurned, metricType: .calories, unit: .kilocalorie(), context: context, since: startDate)
            try await syncQuantity(.heartRateVariabilitySDNN, metricType: .hrv, unit: .secondUnit(with: .milli), context: context, since: startDate)
            try await syncBloodPressure(context: context, since: startDate)
            try await syncSleep(context: context, since: startDate)

            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: "healthkit-last-sync")
        } catch {
            self.error = "Sync failed: \(error.localizedDescription)"
        }

        isSyncing = false
    }

    // MARK: - Query Helpers

    private func syncQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        metricType: MetricType,
        unit: HKUnit,
        context: ModelContext,
        since startDate: Date,
        multiplier: Double = 1
    ) async throws {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1000
        )

        let samples = try await descriptor.result(for: healthStore)

        for sample in samples {
            let value = sample.quantity.doubleValue(for: unit) * multiplier
            insertIfNew(context: context, timestamp: sample.startDate, type: metricType, value: value)
        }
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

            let typeRaw = MetricType.bloodPressure.rawValue
            let sourceRaw = MeasurementSource.appleHealth.rawValue
            let start = Calendar.current.startOfDay(for: sys.startDate)
            let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!

            let descriptor = FetchDescriptor<Measurement>(
                predicate: #Predicate {
                    $0.timestamp >= start && $0.timestamp < end
                    && $0.metricType.rawValue == typeRaw
                    && $0.source.rawValue == sourceRaw
                }
            )

            let existing = (try? context.fetchCount(descriptor)) ?? 0
            if existing == 0 {
                context.insert(Measurement(
                    timestamp: sys.startDate,
                    metricType: .bloodPressure,
                    value: sysValue,
                    value2: diaValue,
                    source: .appleHealth
                ))
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
                // Only count asleep states (not inBed)
                if sample.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue
                    || sample.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue
                    || sample.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
                    || sample.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue {
                    return total + sample.endDate.timeIntervalSince(sample.startDate) / 3600
                }
                return total
            }

            if totalSleep > 0 {
                insertIfNew(context: context, timestamp: night, type: .sleepDuration, value: totalSleep)
            }
        }
    }

    private func insertIfNew(context: ModelContext, timestamp: Date, type: MetricType, value: Double) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: timestamp)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let typeRaw = type.rawValue
        let sourceRaw = MeasurementSource.appleHealth.rawValue

        let descriptor = FetchDescriptor<Measurement>(
            predicate: #Predicate {
                $0.timestamp >= start && $0.timestamp < end
                && $0.metricType.rawValue == typeRaw
                && $0.source.rawValue == sourceRaw
            }
        )

        let existing = (try? context.fetchCount(descriptor)) ?? 0
        if existing == 0 {
            context.insert(Measurement(timestamp: timestamp, metricType: type, value: value, source: .appleHealth))
        }
    }
}
