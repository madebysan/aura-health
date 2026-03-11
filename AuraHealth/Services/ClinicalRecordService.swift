import Foundation
import SwiftData
import HealthKit
import os

private let logger = Logger(subsystem: "com.santiagoalonso.aurahealth", category: "ClinicalRecords")

/// Reads clinical health records (lab results, medications, conditions) from Apple Health.
/// Users connect their healthcare providers in Settings > Health > Health Records,
/// then Aura reads the FHIR R4 resources via HealthKit.
@Observable
@MainActor
final class ClinicalRecordService {
    var isSyncing = false
    var lastSyncDate: Date?
    var error: String?
    var syncSummary: SyncSummary?

    struct SyncSummary {
        var labResults = 0
        var medications = 0
        var conditions = 0
        var vitals = 0
    }

    private let healthStore = HKHealthStore()

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    var isAuthorized: Bool {
        UserDefaults.standard.bool(forKey: "clinical-records-authorized")
    }

    init() {
        if let lastSync = UserDefaults.standard.object(forKey: "clinical-records-last-sync") as? Date {
            self.lastSyncDate = lastSync
        }
    }

    // Clinical record types we want to read
    private var clinicalTypes: Set<HKClinicalType> {
        var types = Set<HKClinicalType>()
        if let lab = HKClinicalType.clinicalType(forIdentifier: .labResultRecord) { types.insert(lab) }
        if let med = HKClinicalType.clinicalType(forIdentifier: .medicationRecord) { types.insert(med) }
        if let cond = HKClinicalType.clinicalType(forIdentifier: .conditionRecord) { types.insert(cond) }
        if let vital = HKClinicalType.clinicalType(forIdentifier: .vitalSignRecord) { types.insert(vital) }
        if let allergy = HKClinicalType.clinicalType(forIdentifier: .allergyRecord) { types.insert(allergy) }
        if let immunization = HKClinicalType.clinicalType(forIdentifier: .immunizationRecord) { types.insert(immunization) }
        return types
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        guard isAvailable else {
            error = "HealthKit is not available on this device"
            return
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: clinicalTypes)
            UserDefaults.standard.set(true, forKey: "clinical-records-authorized")
            error = nil
            logger.notice("[ClinicalRecords] Authorization granted")
        } catch {
            self.error = "Authorization failed: \(error.localizedDescription)"
            logger.error("[ClinicalRecords] Authorization failed: \(error.localizedDescription)")
        }
    }

    func disconnect() {
        UserDefaults.standard.removeObject(forKey: "clinical-records-authorized")
        UserDefaults.standard.removeObject(forKey: "clinical-records-last-sync")
        lastSyncDate = nil
        error = nil
    }

    // MARK: - Sync

    func syncRecords(into context: ModelContext) async {
        guard isAvailable else { return }

        if !isAuthorized {
            await requestAuthorization()
            guard isAuthorized else { return }
        }

        isSyncing = true
        error = nil
        syncSummary = SyncSummary()

        do {
            try await syncLabResults(into: context)
            try await syncMedications(into: context)
            try await syncConditions(into: context)
            try await syncVitalSigns(into: context)

            try? context.save()
            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: "clinical-records-last-sync")

            if let summary = syncSummary {
                logger.notice("[ClinicalRecords] Sync complete: \(summary.labResults) labs, \(summary.medications) meds, \(summary.conditions) conditions, \(summary.vitals) vitals")
            }
        } catch {
            self.error = "Sync failed: \(error.localizedDescription)"
            logger.error("[ClinicalRecords] Sync failed: \(error.localizedDescription)")
        }

        isSyncing = false
    }

    // MARK: - Lab Results -> Biomarker

    private func syncLabResults(into context: ModelContext) async throws {
        guard let type = HKClinicalType.clinicalType(forIdentifier: .labResultRecord) else { return }

        let records = try await fetchClinicalRecords(type: type)
        logger.notice("[ClinicalRecords] Found \(records.count) lab result records")

        for record in records {
            guard let fhir = record.fhirResource,
                  let json = try? JSONSerialization.jsonObject(with: fhir.data) as? [String: Any] else { continue }

            // FHIR Observation resource for lab results
            guard let resourceType = json["resourceType"] as? String, resourceType == "Observation" else { continue }

            // Extract marker name from code.coding
            guard let code = json["code"] as? [String: Any],
                  let codings = code["coding"] as? [[String: Any]],
                  let markerName = codings.first?["display"] as? String else { continue }

            // Extract value
            var value: Double?
            var unit = ""
            if let valueQuantity = json["valueQuantity"] as? [String: Any] {
                value = valueQuantity["value"] as? Double
                unit = valueQuantity["unit"] as? String ?? valueQuantity["code"] as? String ?? ""
            }

            guard let val = value else { continue }

            // Extract reference range
            var refMin: Double?
            var refMax: Double?
            if let refRanges = json["referenceRange"] as? [[String: Any]], let range = refRanges.first {
                if let low = range["low"] as? [String: Any] {
                    refMin = low["value"] as? Double
                }
                if let high = range["high"] as? [String: Any] {
                    refMax = high["value"] as? Double
                }
            }

            // Extract date
            let effectiveDate = parseFHIRDate(json["effectiveDateTime"] as? String) ?? record.startDate

            // Extract source/lab name
            let labName = extractSourceName(from: json) ?? "Clinical Record"

            // Dedup: skip if we already have this marker on this date from clinical records
            let markerDay = Calendar.current.startOfDay(for: effectiveDate)
            let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: markerDay)!
            let descriptor = FetchDescriptor<Biomarker>(
                predicate: #Predicate { $0.testDate >= markerDay && $0.testDate < nextDay }
            )
            let existing = (try? context.fetch(descriptor)) ?? []
            if existing.contains(where: { $0.marker == markerName && $0.lab == labName }) { continue }

            context.insert(Biomarker(
                testDate: effectiveDate,
                marker: markerName,
                value: val,
                unit: unit,
                refMin: refMin,
                refMax: refMax,
                lab: labName,
                notes: "Imported from Apple Health Records"
            ))
            syncSummary?.labResults += 1
        }
    }

    // MARK: - Medications -> Medication

    private func syncMedications(into context: ModelContext) async throws {
        guard let type = HKClinicalType.clinicalType(forIdentifier: .medicationRecord) else { return }

        let records = try await fetchClinicalRecords(type: type)
        logger.notice("[ClinicalRecords] Found \(records.count) medication records")

        for record in records {
            guard let fhir = record.fhirResource,
                  let json = try? JSONSerialization.jsonObject(with: fhir.data) as? [String: Any] else { continue }

            // FHIR MedicationRequest or MedicationStatement
            let resourceType = json["resourceType"] as? String ?? ""
            guard resourceType == "MedicationRequest" || resourceType == "MedicationStatement" else { continue }

            // Extract medication name
            var medName: String?
            if let medicationCodeableConcept = json["medicationCodeableConcept"] as? [String: Any],
               let codings = medicationCodeableConcept["coding"] as? [[String: Any]] {
                medName = codings.first?["display"] as? String
            }
            // Fallback to text
            if medName == nil, let medicationCodeableConcept = json["medicationCodeableConcept"] as? [String: Any] {
                medName = medicationCodeableConcept["text"] as? String
            }

            guard let name = medName, !name.isEmpty else { continue }

            // Extract dosage
            var dosage = ""
            if let dosageInstructions = json["dosageInstruction"] as? [[String: Any]],
               let first = dosageInstructions.first {
                if let text = first["text"] as? String {
                    dosage = text
                } else if let doseAndRate = first["doseAndRate"] as? [[String: Any]],
                          let dose = doseAndRate.first?["doseQuantity"] as? [String: Any] {
                    let doseValue = dose["value"] as? Double ?? 0
                    let doseUnit = dose["unit"] as? String ?? ""
                    dosage = "\(Int(doseValue)) \(doseUnit)"
                }
            }

            // Check if this medication already exists
            let descriptor = FetchDescriptor<Medication>(
                predicate: #Predicate { $0.name == name }
            )
            let existing = (try? context.fetch(descriptor)) ?? []
            if !existing.isEmpty { continue }

            // Extract dates
            let startDate = parseFHIRDate(json["authoredOn"] as? String) ?? record.startDate

            context.insert(Medication(
                name: name,
                dosage: dosage,
                frequency: .daily,
                condition: "Imported from clinical records",
                type: .rx,
                timing: .anyTime,
                startDate: startDate
            ))
            syncSummary?.medications += 1
        }
    }

    // MARK: - Conditions -> Condition

    private func syncConditions(into context: ModelContext) async throws {
        guard let type = HKClinicalType.clinicalType(forIdentifier: .conditionRecord) else { return }

        let records = try await fetchClinicalRecords(type: type)
        logger.notice("[ClinicalRecords] Found \(records.count) condition records")

        for record in records {
            guard let fhir = record.fhirResource,
                  let json = try? JSONSerialization.jsonObject(with: fhir.data) as? [String: Any] else { continue }

            guard let resourceType = json["resourceType"] as? String, resourceType == "Condition" else { continue }

            // Extract condition name
            guard let code = json["code"] as? [String: Any],
                  let codings = code["coding"] as? [[String: Any]],
                  let conditionName = codings.first?["display"] as? String else { continue }

            // Check for duplicates
            let descriptor = FetchDescriptor<Condition>(
                predicate: #Predicate { $0.name == conditionName }
            )
            let existing = (try? context.fetch(descriptor)) ?? []
            if !existing.isEmpty { continue }

            // Extract clinical status
            var status: ConditionStatus = .active
            if let clinicalStatus = json["clinicalStatus"] as? [String: Any],
               let statusCodings = clinicalStatus["coding"] as? [[String: Any]],
               let statusCode = statusCodings.first?["code"] as? String {
                switch statusCode {
                case "resolved", "remission", "inactive": status = .resolved
                case "active", "recurrence", "relapse": status = .active
                default: status = .managed
                }
            }

            // Extract onset date
            let onsetDate = parseFHIRDate(json["onsetDateTime"] as? String)

            context.insert(Condition(
                name: conditionName,
                status: status,
                diagnosedDate: onsetDate ?? record.startDate,
                notes: "Imported from Apple Health Records"
            ))
            syncSummary?.conditions += 1
        }
    }

    // MARK: - Vital Signs -> Measurement

    private func syncVitalSigns(into context: ModelContext) async throws {
        guard let type = HKClinicalType.clinicalType(forIdentifier: .vitalSignRecord) else { return }

        let records = try await fetchClinicalRecords(type: type)
        logger.notice("[ClinicalRecords] Found \(records.count) vital sign records")

        for record in records {
            guard let fhir = record.fhirResource,
                  let json = try? JSONSerialization.jsonObject(with: fhir.data) as? [String: Any] else { continue }

            guard let resourceType = json["resourceType"] as? String, resourceType == "Observation" else { continue }

            // Map LOINC codes to MetricType
            guard let code = json["code"] as? [String: Any],
                  let codings = code["coding"] as? [[String: Any]] else { continue }

            let loincCode = codings.first(where: { ($0["system"] as? String)?.contains("loinc") == true })?["code"] as? String ?? ""

            guard let metricType = mapLoincToMetricType(loincCode) else { continue }

            // Extract value
            guard let valueQuantity = json["valueQuantity"] as? [String: Any],
                  let value = valueQuantity["value"] as? Double else { continue }

            let effectiveDate = parseFHIRDate(json["effectiveDateTime"] as? String) ?? record.startDate
            let day = Calendar.current.startOfDay(for: effectiveDate)
            let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day)!

            // Dedup
            let descriptor = FetchDescriptor<Measurement>(
                predicate: #Predicate { $0.timestamp >= day && $0.timestamp < nextDay }
            )
            let existing = (try? context.fetch(descriptor)) ?? []
            if existing.contains(where: { $0.metricType == metricType && $0.source == .clinicalRecord }) { continue }

            // Handle blood pressure (dual value)
            var value2: Double?
            if metricType == .bloodPressure {
                if let components = json["component"] as? [[String: Any]] {
                    for comp in components {
                        if let compCode = comp["code"] as? [String: Any],
                           let compCodings = compCode["coding"] as? [[String: Any]],
                           let compLoinc = compCodings.first?["code"] as? String,
                           compLoinc == "8462-4", // diastolic
                           let compValue = (comp["valueQuantity"] as? [String: Any])?["value"] as? Double {
                            value2 = compValue
                        }
                    }
                }
            }

            context.insert(Measurement(
                timestamp: effectiveDate,
                metricType: metricType,
                value: value,
                value2: value2,
                source: .clinicalRecord,
                notes: "From clinical records"
            ))
            syncSummary?.vitals += 1
        }
    }

    // MARK: - Helpers

    private func fetchClinicalRecords(type: HKClinicalType) async throws -> [HKClinicalRecord] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.clinicalRecord(type: type)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 5000
        )
        return try await descriptor.result(for: healthStore)
    }

    private func parseFHIRDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        // FHIR dates: "2026-03-01", "2026-03-01T10:30:00Z", "2026-03-01T10:30:00+05:00"
        let formatters: [DateFormatter] = {
            let f1 = DateFormatter()
            f1.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            let f2 = DateFormatter()
            f2.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
            let f3 = DateFormatter()
            f3.dateFormat = "yyyy-MM-dd"
            return [f1, f2, f3]
        }()
        for formatter in formatters {
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }

    private func extractSourceName(from json: [String: Any]) -> String? {
        // Try performer -> organization -> display
        if let performers = json["performer"] as? [[String: Any]],
           let performer = performers.first,
           let display = performer["display"] as? String {
            return display
        }
        return nil
    }

    /// Maps common LOINC vital sign codes to MetricType
    private func mapLoincToMetricType(_ loincCode: String) -> MetricType? {
        switch loincCode {
        case "85354-9", "8480-6": return .bloodPressure  // BP panel, systolic
        case "8867-4": return .heartRate
        case "29463-7", "3141-9": return .weight
        case "8310-5": return .skinTemp // body temperature
        case "2708-6", "59408-5": return .spo2
        case "80404-7": return .hrv // HRV SDNN
        default: return nil
        }
    }
}
