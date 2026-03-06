import Foundation
import SwiftData
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// JSON import/export for full database backup
struct ImportExportService {

    // MARK: - Export

    static func exportAllData(from context: ModelContext) throws -> Data {
        var export = ExportData()

        export.measurements = ((try? context.fetch(FetchDescriptor<Measurement>())) ?? []).map { MeasurementExport(from: $0) }
        export.medications = ((try? context.fetch(FetchDescriptor<Medication>())) ?? []).map { MedicationExport(from: $0) }
        export.medicationLogs = ((try? context.fetch(FetchDescriptor<MedicationLog>())) ?? []).map { MedicationLogExport(from: $0) }
        export.biomarkers = ((try? context.fetch(FetchDescriptor<Biomarker>())) ?? []).map { BiomarkerExport(from: $0) }
        export.habits = ((try? context.fetch(FetchDescriptor<Habit>())) ?? []).map { HabitExport(from: $0) }
        export.habitLogs = ((try? context.fetch(FetchDescriptor<HabitLog>())) ?? []).map { HabitLogExport(from: $0) }
        export.conditions = ((try? context.fetch(FetchDescriptor<Condition>())) ?? []).map { ConditionExport(from: $0) }
        export.dietPlans = ((try? context.fetch(FetchDescriptor<DietPlan>())) ?? []).map { DietPlanExport(from: $0) }
        export.metricRanges = ((try? context.fetch(FetchDescriptor<MetricRange>())) ?? []).map { MetricRangeExport(from: $0) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(export)
    }

    // MARK: - Import

    static func importData(_ data: Data, into context: ModelContext) throws -> ImportResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let imported = try decoder.decode(ExportData.self, from: data)

        var result = ImportResult()

        for m in imported.measurements {
            context.insert(m.toModel())
            result.measurements += 1
        }
        for m in imported.biomarkers {
            context.insert(m.toModel())
            result.biomarkers += 1
        }
        for m in imported.conditions {
            context.insert(m.toModel())
            result.conditions += 1
        }
        for m in imported.dietPlans {
            context.insert(m.toModel())
            result.dietPlans += 1
        }
        for m in imported.metricRanges {
            context.insert(m.toModel())
            result.metricRanges += 1
        }

        // Medications + logs need relationship linking
        var medicationMap: [UUID: Medication] = [:]
        for m in imported.medications {
            let med = m.toModel()
            context.insert(med)
            medicationMap[m.id] = med
            result.medications += 1
        }
        for log in imported.medicationLogs {
            if let med = medicationMap[log.medicationId] {
                context.insert(log.toModel(medication: med))
                result.medicationLogs += 1
            }
        }

        var habitMap: [UUID: Habit] = [:]
        for h in imported.habits {
            let habit = h.toModel()
            context.insert(habit)
            habitMap[h.id] = habit
            result.habits += 1
        }
        for log in imported.habitLogs {
            if let habit = habitMap[log.habitId] {
                context.insert(log.toModel(habit: habit))
                result.habitLogs += 1
            }
        }

        try context.save()
        return result
    }
}

// MARK: - Import Result

struct ImportResult {
    var measurements = 0
    var medications = 0
    var medicationLogs = 0
    var biomarkers = 0
    var habits = 0
    var habitLogs = 0
    var conditions = 0
    var dietPlans = 0
    var metricRanges = 0

    var summary: String {
        var parts: [String] = []
        if measurements > 0 { parts.append("\(measurements) measurements") }
        if medications > 0 { parts.append("\(medications) medications") }
        if medicationLogs > 0 { parts.append("\(medicationLogs) med logs") }
        if biomarkers > 0 { parts.append("\(biomarkers) biomarkers") }
        if habits > 0 { parts.append("\(habits) habits") }
        if habitLogs > 0 { parts.append("\(habitLogs) habit logs") }
        if conditions > 0 { parts.append("\(conditions) conditions") }
        if dietPlans > 0 { parts.append("\(dietPlans) diet plans") }
        if metricRanges > 0 { parts.append("\(metricRanges) metric ranges") }
        return parts.isEmpty ? "No data imported" : "Imported: " + parts.joined(separator: ", ")
    }
}

// MARK: - Export Container

struct ExportData: Codable {
    var version = 1
    var exportDate = Date()
    var measurements: [MeasurementExport] = []
    var medications: [MedicationExport] = []
    var medicationLogs: [MedicationLogExport] = []
    var biomarkers: [BiomarkerExport] = []
    var habits: [HabitExport] = []
    var habitLogs: [HabitLogExport] = []
    var conditions: [ConditionExport] = []
    var dietPlans: [DietPlanExport] = []
    var metricRanges: [MetricRangeExport] = []
}

// MARK: - Export/Import Models

struct MeasurementExport: Codable {
    let id: UUID; let timestamp: Date; let metricType: String
    let value: Double; let value2: Double?; let unit: String
    let source: String; let notes: String

    init(from m: Measurement) {
        id = m.id; timestamp = m.timestamp; metricType = m.metricType.rawValue
        value = m.value; value2 = m.value2; unit = m.unit
        source = m.source.rawValue; notes = m.notes
    }

    func toModel() -> Measurement {
        Measurement(timestamp: timestamp,
            metricType: MetricType(rawValue: metricType) ?? .weight,
            value: value, value2: value2, unit: unit,
            source: MeasurementSource(rawValue: source) ?? .manual,
            notes: notes)
    }
}

struct MedicationExport: Codable {
    let id: UUID; let name: String; let dosage: String
    let frequency: String; let condition: String; let type: String
    let timing: String; let startDate: Date?; let endDate: Date?
    let active: Bool

    init(from m: Medication) {
        id = m.id; name = m.name; dosage = m.dosage
        frequency = m.frequency.rawValue; condition = m.condition
        type = m.type.rawValue; timing = m.timing.rawValue
        startDate = m.startDate; endDate = m.endDate; active = m.active
    }

    func toModel() -> Medication {
        Medication(name: name, dosage: dosage,
            frequency: MedicationFrequency(rawValue: frequency) ?? .daily,
            condition: condition,
            type: MedicationType(rawValue: type) ?? .rx,
            timing: MedicationTiming(rawValue: timing) ?? .anyTime,
            startDate: startDate, endDate: endDate)
    }
}

struct MedicationLogExport: Codable {
    let id: UUID; let date: Date; let medicationId: UUID
    let taken: Bool; let dosage: String; let notes: String

    init(from log: MedicationLog) {
        id = log.id; date = log.date; medicationId = log.medication?.id ?? UUID()
        taken = log.taken; dosage = log.dosage; notes = log.notes
    }

    func toModel(medication: Medication) -> MedicationLog {
        MedicationLog(date: date, medication: medication, taken: taken, dosage: dosage, notes: notes)
    }
}

struct BiomarkerExport: Codable {
    let id: UUID; let testDate: Date; let marker: String
    let value: Double; let unit: String; let refMin: Double?
    let refMax: Double?; let lab: String; let notes: String

    init(from b: Biomarker) {
        id = b.id; testDate = b.testDate; marker = b.marker
        value = b.value; unit = b.unit; refMin = b.refMin
        refMax = b.refMax; lab = b.lab; notes = b.notes
    }

    func toModel() -> Biomarker {
        Biomarker(testDate: testDate, marker: marker, value: value,
            unit: unit, refMin: refMin, refMax: refMax, lab: lab, notes: notes)
    }
}

struct HabitExport: Codable {
    let id: UUID; let name: String; let category: String
    let trackingType: String; let frequency: String
    let unit: String; let active: Bool

    init(from h: Habit) {
        id = h.id; name = h.name; category = h.category.rawValue
        trackingType = h.trackingType.rawValue; frequency = h.frequency
        unit = h.unit; active = h.active
    }

    func toModel() -> Habit {
        Habit(name: name,
            category: HabitCategory(rawValue: category) ?? .lifestyle,
            trackingType: TrackingType(rawValue: trackingType) ?? .boolean,
            frequency: frequency, unit: unit)
    }
}

struct HabitLogExport: Codable {
    let id: UUID; let date: Date; let habitId: UUID
    let done: Bool; let quantity: Double?; let unit: String; let notes: String

    init(from log: HabitLog) {
        id = log.id; date = log.date; habitId = log.habit?.id ?? UUID()
        done = log.done; quantity = log.quantity; unit = log.unit; notes = log.notes
    }

    func toModel(habit: Habit) -> HabitLog {
        HabitLog(date: date, habit: habit, done: done, quantity: quantity, unit: unit, notes: notes)
    }
}

struct ConditionExport: Codable {
    let id: UUID; let name: String; let status: String
    let diagnosedDate: Date?; let notes: String

    init(from c: Condition) {
        id = c.id; name = c.name; status = c.status.rawValue
        diagnosedDate = c.diagnosedDate; notes = c.notes
    }

    func toModel() -> Condition {
        Condition(name: name,
            status: ConditionStatus(rawValue: status) ?? .active,
            diagnosedDate: diagnosedDate, notes: notes)
    }
}

struct DietPlanExport: Codable {
    let id: UUID; let name: String; let dietType: String
    let startDate: Date?; let endDate: Date?; let active: Bool; let notes: String

    init(from d: DietPlan) {
        id = d.id; name = d.name; dietType = d.dietType
        startDate = d.startDate; endDate = d.endDate; active = d.active; notes = d.notes
    }

    func toModel() -> DietPlan {
        DietPlan(name: name, dietType: dietType,
            startDate: startDate, endDate: endDate, notes: notes)
    }
}

struct MetricRangeExport: Codable {
    let id: UUID; let metricType: String; let low: Double; let high: Double

    init(from r: MetricRange) {
        id = r.id; metricType = r.metricType.rawValue; low = r.low; high = r.high
    }

    func toModel() -> MetricRange {
        MetricRange(metricType: MetricType(rawValue: metricType) ?? .weight, low: low, high: high)
    }
}
