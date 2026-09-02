import Foundation
import SwiftData

/// Versioned JSON backup and restore for every user-owned Aura record.
enum ImportExportService {
    static let currentBackupVersion = 2

    enum ImportMode {
        case merge
        case replace
    }

    @MainActor
    static func exportAllData(from context: ModelContext) throws -> Data {
        var export = ExportData()
        export.measurements = try context.fetch(FetchDescriptor<AuraHealth.Measurement>()).map(MeasurementExport.init)
        export.medications = try context.fetch(FetchDescriptor<Medication>()).map(MedicationExport.init)
        export.medicationLogs = try context.fetch(FetchDescriptor<MedicationLog>()).compactMap(MedicationLogExport.init)
        export.biomarkers = try context.fetch(FetchDescriptor<Biomarker>()).map(BiomarkerExport.init)
        export.habits = try context.fetch(FetchDescriptor<Habit>()).map(HabitExport.init)
        export.habitLogs = try context.fetch(FetchDescriptor<HabitLog>()).compactMap(HabitLogExport.init)
        export.conditions = try context.fetch(FetchDescriptor<Condition>()).map(ConditionExport.init)
        export.dietPlans = try context.fetch(FetchDescriptor<DietPlan>()).map(DietPlanExport.init)
        export.metricRanges = try context.fetch(FetchDescriptor<MetricRange>()).map(MetricRangeExport.init)
        export.conversations = try context.fetch(FetchDescriptor<Conversation>()).map(ConversationExport.init)
        export.vaultDocuments = try context.fetch(FetchDescriptor<VaultDocument>()).map(VaultDocumentExport.init)
        export.healthMemories = try context.fetch(FetchDescriptor<HealthMemory>()).map(HealthMemoryExport.init)
        export.labSessions = try context.fetch(FetchDescriptor<LabSession>()).map(LabSessionExport.init)
        export.smartHabits = try context.fetch(FetchDescriptor<SmartHabit>()).map(SmartHabitExport.init)
        export.protocolMetadata = try context.fetch(FetchDescriptor<ProtocolMeta>()).map(ProtocolMetaExport.init)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(export)
    }

    @discardableResult
    @MainActor
    static func importData(
        _ data: Data,
        into context: ModelContext,
        mode: ImportMode = .merge
    ) throws -> ImportResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let imported = try decoder.decode(ExportData.self, from: data)

        guard imported.version <= currentBackupVersion else {
            throw BackupError.unsupportedVersion(imported.version)
        }

        if mode == .replace {
            try DataLifecycleService.clearDatabase(from: context)
        }

        var result = ImportResult()
        let existingMeasurementIDs = try ids(in: context, for: AuraHealth.Measurement.self)
        let existingMedicationIDs = try ids(in: context, for: Medication.self)
        let existingMedicationLogIDs = try ids(in: context, for: MedicationLog.self)
        let existingBiomarkerIDs = try ids(in: context, for: Biomarker.self)
        let existingHabitIDs = try ids(in: context, for: Habit.self)
        let existingHabitLogIDs = try ids(in: context, for: HabitLog.self)
        let existingConditionIDs = try ids(in: context, for: Condition.self)
        let existingDietPlanIDs = try ids(in: context, for: DietPlan.self)
        let existingMetricRangeIDs = try ids(in: context, for: MetricRange.self)
        let existingConversationIDs = try ids(in: context, for: Conversation.self)
        let existingVaultDocumentIDs = try ids(in: context, for: VaultDocument.self)
        let existingHealthMemoryIDs = try ids(in: context, for: HealthMemory.self)
        let existingLabSessionIDs = try ids(in: context, for: LabSession.self)
        let existingSmartHabitIDs = try ids(in: context, for: SmartHabit.self)
        let existingProtocolMetaIDs = try ids(in: context, for: ProtocolMeta.self)

        for item in imported.measurements where !existingMeasurementIDs.contains(item.id) {
            context.insert(item.toModel())
            result.measurements += 1
        }

        var medicationMap = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Medication>()).map { ($0.id, $0) })
        for item in imported.medications where !existingMedicationIDs.contains(item.id) {
            let model = item.toModel()
            context.insert(model)
            medicationMap[item.id] = model
            result.medications += 1
        }
        for item in imported.medicationLogs where !existingMedicationLogIDs.contains(item.id) {
            guard let medication = medicationMap[item.medicationID] else { continue }
            context.insert(item.toModel(medication: medication))
            result.medicationLogs += 1
        }

        for item in imported.biomarkers where !existingBiomarkerIDs.contains(item.id) {
            context.insert(item.toModel())
            result.biomarkers += 1
        }

        var habitMap = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Habit>()).map { ($0.id, $0) })
        for item in imported.habits where !existingHabitIDs.contains(item.id) {
            let model = item.toModel()
            context.insert(model)
            habitMap[item.id] = model
            result.habits += 1
        }
        for item in imported.habitLogs where !existingHabitLogIDs.contains(item.id) {
            guard let habit = habitMap[item.habitID] else { continue }
            context.insert(item.toModel(habit: habit))
            result.habitLogs += 1
        }

        for item in imported.conditions where !existingConditionIDs.contains(item.id) {
            context.insert(item.toModel())
            result.conditions += 1
        }
        for item in imported.dietPlans where !existingDietPlanIDs.contains(item.id) {
            context.insert(item.toModel())
            result.dietPlans += 1
        }
        for item in imported.metricRanges where !existingMetricRangeIDs.contains(item.id) {
            context.insert(item.toModel())
            result.metricRanges += 1
        }
        for item in imported.conversations where !existingConversationIDs.contains(item.id) {
            context.insert(item.toModel())
            result.conversations += 1
        }
        for item in imported.vaultDocuments where !existingVaultDocumentIDs.contains(item.id) {
            context.insert(item.toModel())
            result.vaultDocuments += 1
        }
        for item in imported.healthMemories where !existingHealthMemoryIDs.contains(item.id) {
            context.insert(item.toModel())
            result.healthMemories += 1
        }
        for item in imported.labSessions where !existingLabSessionIDs.contains(item.id) {
            context.insert(item.toModel())
            result.labSessions += 1
        }
        for item in imported.smartHabits where !existingSmartHabitIDs.contains(item.id) {
            context.insert(item.toModel())
            result.smartHabits += 1
        }
        for item in imported.protocolMetadata where !existingProtocolMetaIDs.contains(item.id) {
            context.insert(item.toModel())
            result.protocolMetadata += 1
        }

        try context.save()
        return result
    }

    @MainActor
    private static func ids<T: PersistentModel & Identifiable>(
        in context: ModelContext,
        for type: T.Type
    ) throws -> Set<UUID> where T.ID == UUID {
        Set(try context.fetch(FetchDescriptor<T>()).map(\.id))
    }
}

enum BackupError: LocalizedError {
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "This backup was created by a newer version of Aura (format \(version))."
        }
    }
}

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
    var conversations = 0
    var vaultDocuments = 0
    var healthMemories = 0
    var labSessions = 0
    var smartHabits = 0
    var protocolMetadata = 0

    var total: Int {
        measurements + medications + medicationLogs + biomarkers + habits + habitLogs
            + conditions + dietPlans + metricRanges + conversations + vaultDocuments
            + healthMemories + labSessions + smartHabits + protocolMetadata
    }

    var summary: String {
        total == 0 ? "No new data imported" : "Imported \(total) records"
    }
}

struct ExportData: Codable {
    var version = ImportExportService.currentBackupVersion
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
    var conversations: [ConversationExport] = []
    var vaultDocuments: [VaultDocumentExport] = []
    var healthMemories: [HealthMemoryExport] = []
    var labSessions: [LabSessionExport] = []
    var smartHabits: [SmartHabitExport] = []
    var protocolMetadata: [ProtocolMetaExport] = []

    private enum CodingKeys: String, CodingKey {
        case version, exportDate, measurements, medications, medicationLogs, biomarkers
        case habits, habitLogs, conditions, dietPlans, metricRanges, conversations
        case vaultDocuments, healthMemories, labSessions, smartHabits, protocolMetadata
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        exportDate = try container.decodeIfPresent(Date.self, forKey: .exportDate) ?? Date()
        measurements = try container.decodeIfPresent([MeasurementExport].self, forKey: .measurements) ?? []
        medications = try container.decodeIfPresent([MedicationExport].self, forKey: .medications) ?? []
        medicationLogs = try container.decodeIfPresent([MedicationLogExport].self, forKey: .medicationLogs) ?? []
        biomarkers = try container.decodeIfPresent([BiomarkerExport].self, forKey: .biomarkers) ?? []
        habits = try container.decodeIfPresent([HabitExport].self, forKey: .habits) ?? []
        habitLogs = try container.decodeIfPresent([HabitLogExport].self, forKey: .habitLogs) ?? []
        conditions = try container.decodeIfPresent([ConditionExport].self, forKey: .conditions) ?? []
        dietPlans = try container.decodeIfPresent([DietPlanExport].self, forKey: .dietPlans) ?? []
        metricRanges = try container.decodeIfPresent([MetricRangeExport].self, forKey: .metricRanges) ?? []
        conversations = try container.decodeIfPresent([ConversationExport].self, forKey: .conversations) ?? []
        vaultDocuments = try container.decodeIfPresent([VaultDocumentExport].self, forKey: .vaultDocuments) ?? []
        healthMemories = try container.decodeIfPresent([HealthMemoryExport].self, forKey: .healthMemories) ?? []
        labSessions = try container.decodeIfPresent([LabSessionExport].self, forKey: .labSessions) ?? []
        smartHabits = try container.decodeIfPresent([SmartHabitExport].self, forKey: .smartHabits) ?? []
        protocolMetadata = try container.decodeIfPresent([ProtocolMetaExport].self, forKey: .protocolMetadata) ?? []
    }
}

struct MeasurementExport: Codable {
    let id: UUID; let timestamp: Date; let metricType: String
    let value: Double; let value2: Double?; let unit: String
    let source: String; let notes: String

    init(_ model: AuraHealth.Measurement) {
        id = model.id; timestamp = model.timestamp; metricType = model.metricType.rawValue
        value = model.value; value2 = model.value2; unit = model.unit
        source = model.source.rawValue; notes = model.notes
    }

    func toModel() -> AuraHealth.Measurement {
        let model = AuraHealth.Measurement(timestamp: timestamp,
            metricType: MetricType(rawValue: metricType) ?? .weight,
            value: value, value2: value2, unit: unit,
            source: MeasurementSource(rawValue: source) ?? .manual, notes: notes)
        model.id = id
        return model
    }
}

struct MedicationExport: Codable {
    let id: UUID; let name: String; let dosage: String
    let frequency: String; let condition: String; let type: String
    let timing: String; let startDate: Date?; let endDate: Date?
    let active: Bool; let gridSection: String?; let gridOrder: Int?

    init(_ model: Medication) {
        id = model.id; name = model.name; dosage = model.dosage
        frequency = model.frequency.rawValue; condition = model.condition
        type = model.type.rawValue; timing = model.timing.rawValue
        startDate = model.startDate; endDate = model.endDate; active = model.active
        gridSection = model.gridSection.rawValue; gridOrder = model.gridOrder
    }

    func toModel() -> Medication {
        let model = Medication(name: name, dosage: dosage,
            frequency: MedicationFrequency(rawValue: frequency) ?? .daily,
            condition: condition, type: MedicationType(rawValue: type) ?? .rx,
            timing: MedicationTiming(rawValue: timing) ?? .anyTime,
            startDate: startDate, endDate: endDate,
            gridSection: gridSection.flatMap(GridSection.init(rawValue:)) ?? .morning,
            gridOrder: gridOrder ?? 0)
        model.id = id; model.active = active
        return model
    }
}

struct MedicationLogExport: Codable {
    let id: UUID; let date: Date; let medicationID: UUID
    let taken: Bool; let dosage: String; let notes: String

    private enum CodingKeys: String, CodingKey { case id, date, medicationID, medicationId, taken, dosage, notes }

    init?(_ model: MedicationLog) {
        guard let medicationID = model.medication?.id else { return nil }
        id = model.id; date = model.date; self.medicationID = medicationID
        taken = model.taken; dosage = model.dosage; notes = model.notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        medicationID = try container.decodeIfPresent(UUID.self, forKey: .medicationID)
            ?? container.decode(UUID.self, forKey: .medicationId)
        taken = try container.decode(Bool.self, forKey: .taken)
        dosage = try container.decode(String.self, forKey: .dosage)
        notes = try container.decode(String.self, forKey: .notes)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id); try container.encode(date, forKey: .date)
        try container.encode(medicationID, forKey: .medicationID)
        try container.encode(taken, forKey: .taken); try container.encode(dosage, forKey: .dosage)
        try container.encode(notes, forKey: .notes)
    }

    func toModel(medication: Medication) -> MedicationLog {
        let model = MedicationLog(date: date, medication: medication, taken: taken, dosage: dosage, notes: notes)
        model.id = id
        return model
    }
}

struct BiomarkerExport: Codable {
    let id: UUID; let testDate: Date; let marker: String; let value: Double; let unit: String
    let refMin: Double?; let refMax: Double?; let targetMin: Double?; let targetMax: Double?
    let lab: String; let notes: String

    init(_ model: Biomarker) {
        id = model.id; testDate = model.testDate; marker = model.marker; value = model.value
        unit = model.unit; refMin = model.refMin; refMax = model.refMax
        targetMin = model.targetMin; targetMax = model.targetMax; lab = model.lab; notes = model.notes
    }

    func toModel() -> Biomarker {
        let model = Biomarker(testDate: testDate, marker: marker, value: value, unit: unit,
            refMin: refMin, refMax: refMax, targetMin: targetMin, targetMax: targetMax,
            lab: lab, notes: notes)
        model.id = id
        return model
    }
}

struct HabitExport: Codable {
    let id: UUID; let name: String; let category: String; let trackingType: String
    let frequency: String; let unit: String; let active: Bool
    let gridSection: String?; let gridOrder: Int?

    init(_ model: Habit) {
        id = model.id; name = model.name; category = model.category.rawValue
        trackingType = model.trackingType.rawValue; frequency = model.frequency
        unit = model.unit; active = model.active
        gridSection = model.gridSection.rawValue; gridOrder = model.gridOrder
    }

    func toModel() -> Habit {
        let model = Habit(name: name, category: HabitCategory(rawValue: category) ?? .lifestyle,
            trackingType: TrackingType(rawValue: trackingType) ?? .boolean,
            frequency: frequency, unit: unit,
            gridSection: gridSection.flatMap(GridSection.init(rawValue:)) ?? .morning,
            gridOrder: gridOrder ?? 0)
        model.id = id; model.active = active
        return model
    }
}

struct HabitLogExport: Codable {
    let id: UUID; let date: Date; let habitID: UUID
    let done: Bool; let quantity: Double?; let unit: String; let notes: String

    private enum CodingKeys: String, CodingKey { case id, date, habitID, habitId, done, quantity, unit, notes }

    init?(_ model: HabitLog) {
        guard let habitID = model.habit?.id else { return nil }
        id = model.id; date = model.date; self.habitID = habitID
        done = model.done; quantity = model.quantity; unit = model.unit; notes = model.notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        habitID = try container.decodeIfPresent(UUID.self, forKey: .habitID)
            ?? container.decode(UUID.self, forKey: .habitId)
        done = try container.decode(Bool.self, forKey: .done)
        quantity = try container.decodeIfPresent(Double.self, forKey: .quantity)
        unit = try container.decode(String.self, forKey: .unit)
        notes = try container.decode(String.self, forKey: .notes)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id); try container.encode(date, forKey: .date)
        try container.encode(habitID, forKey: .habitID); try container.encode(done, forKey: .done)
        try container.encodeIfPresent(quantity, forKey: .quantity)
        try container.encode(unit, forKey: .unit); try container.encode(notes, forKey: .notes)
    }

    func toModel(habit: Habit) -> HabitLog {
        let model = HabitLog(date: date, habit: habit, done: done, quantity: quantity, unit: unit, notes: notes)
        model.id = id
        return model
    }
}

struct ConditionExport: Codable {
    let id: UUID; let name: String; let status: String; let diagnosedDate: Date?; let notes: String

    init(_ model: Condition) {
        id = model.id; name = model.name; status = model.status.rawValue
        diagnosedDate = model.diagnosedDate; notes = model.notes
    }

    func toModel() -> Condition {
        let model = Condition(name: name, status: ConditionStatus(rawValue: status) ?? .active,
            diagnosedDate: diagnosedDate, notes: notes)
        model.id = id
        return model
    }
}

struct DietPlanExport: Codable {
    let id: UUID; let name: String; let dietType: String
    let startDate: Date?; let endDate: Date?; let allowedFoods: [String]?
    let avoidFoods: [String]?; let foodCategories: [String]?; let active: Bool; let notes: String

    init(_ model: DietPlan) {
        id = model.id; name = model.name; dietType = model.dietType
        startDate = model.startDate; endDate = model.endDate
        allowedFoods = model.allowedFoods; avoidFoods = model.avoidFoods
        foodCategories = model.foodCategories; active = model.active; notes = model.notes
    }

    func toModel() -> DietPlan {
        let model = DietPlan(name: name, dietType: dietType, startDate: startDate, endDate: endDate,
            allowedFoods: allowedFoods ?? [], avoidFoods: avoidFoods ?? [],
            foodCategories: foodCategories ?? [], notes: notes)
        model.id = id; model.active = active
        return model
    }
}

struct MetricRangeExport: Codable {
    let id: UUID; let metricType: String; let low: Double; let high: Double

    init(_ model: MetricRange) {
        id = model.id; metricType = model.metricType.rawValue; low = model.low; high = model.high
    }

    func toModel() -> MetricRange {
        let model = MetricRange(metricType: MetricType(rawValue: metricType) ?? .weight, low: low, high: high)
        model.id = id
        return model
    }
}

struct ConversationExport: Codable {
    let id: UUID; let title: String; let messages: [ChatMessage]
    let createdAt: Date; let updatedAt: Date

    init(_ model: Conversation) {
        id = model.id; title = model.title; messages = model.messages
        createdAt = model.createdAt; updatedAt = model.updatedAt
    }

    func toModel() -> Conversation {
        let model = Conversation(title: title)
        model.id = id; model.messages = messages
        model.createdAt = createdAt; model.updatedAt = updatedAt
        return model
    }
}

struct VaultDocumentExport: Codable {
    let id: UUID; let title: String; let fileName: String; let fileType: String
    let mimeType: String; let fileData: Data?; let fileSize: Int; let tags: [String]
    let date: Date?; let uploadedAt: Date; let notes: String

    init(_ model: VaultDocument) {
        id = model.id; title = model.title; fileName = model.fileName
        fileType = model.fileType.rawValue; mimeType = model.mimeType
        fileData = model.fileData; fileSize = model.fileSize; tags = model.tags
        date = model.date; uploadedAt = model.uploadedAt; notes = model.notes
    }

    func toModel() -> VaultDocument {
        let model = VaultDocument(title: title, fileName: fileName,
            fileType: VaultFileType(rawValue: fileType) ?? .text, mimeType: mimeType,
            fileData: fileData, fileSize: fileSize, tags: tags, date: date, notes: notes)
        model.id = id; model.uploadedAt = uploadedAt
        return model
    }
}

struct HealthMemoryExport: Codable {
    let id: UUID; let content: String; let pinned: Bool; let createdAt: Date

    init(_ model: HealthMemory) {
        id = model.id; content = model.content; pinned = model.pinned; createdAt = model.createdAt
    }

    func toModel() -> HealthMemory {
        let model = HealthMemory(content: content, pinned: pinned)
        model.id = id; model.createdAt = createdAt
        return model
    }
}

struct LabSessionExport: Codable {
    let id: UUID; let date: Date; let name: String; let notes: String

    init(_ model: LabSession) {
        id = model.id; date = model.date; name = model.name; notes = model.notes
    }

    func toModel() -> LabSession {
        let model = LabSession(date: date, name: name, notes: notes)
        model.id = id
        return model
    }
}

struct SmartHabitExport: Codable {
    let id: UUID; let date: Date; let name: String; let reason: String
    let gridSection: String; let done: Bool; let dismissed: Bool; let priority: Int

    init(_ model: SmartHabit) {
        id = model.id; date = model.date; name = model.name; reason = model.reason
        gridSection = model.gridSection.rawValue; done = model.done
        dismissed = model.dismissed; priority = model.priority
    }

    func toModel() -> SmartHabit {
        let model = SmartHabit(date: date, name: name, reason: reason,
            gridSection: GridSection(rawValue: gridSection) ?? .morning, priority: priority)
        model.id = id; model.done = done; model.dismissed = dismissed
        return model
    }
}

struct ProtocolMetaExport: Codable {
    let id: UUID; let generatedDate: Date; let forDate: Date; let contextHash: String

    init(_ model: ProtocolMeta) {
        id = model.id; generatedDate = model.generatedDate
        forDate = model.forDate; contextHash = model.contextHash
    }

    func toModel() -> ProtocolMeta {
        let model = ProtocolMeta(forDate: forDate, contextHash: contextHash)
        model.id = id; model.generatedDate = generatedDate
        return model
    }
}
