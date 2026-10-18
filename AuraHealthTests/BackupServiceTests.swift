import XCTest
import SwiftData
@testable import AuraHealth

@MainActor
final class BackupServiceTests: XCTestCase {
    func testRoundTripIncludesEveryUserOwnedRecordAndPreservesIdentifiers() throws {
        let source = try makeContainer()
        let sourceContext = source.mainContext

        let measurement = AuraHealth.Measurement(metricType: .heartRate, value: 68)
        let conversation = Conversation(title: "Health questions")
        conversation.addMessage(role: .user, content: "How is my heart rate trending?")
        let document = VaultDocument(
            title: "Lab report",
            fileName: "labs.pdf",
            fileType: .pdf,
            mimeType: "application/pdf",
            fileData: Data("private report".utf8),
            fileSize: 14,
            tags: ["lab"],
            notes: "Imported for review"
        )
        let memory = HealthMemory(content: "Prefers morning workouts", pinned: true)
        let session = LabSession(date: Date(timeIntervalSince1970: 1_700_000_000), name: "Annual labs")

        sourceContext.insert(measurement)
        sourceContext.insert(conversation)
        sourceContext.insert(document)
        sourceContext.insert(memory)
        sourceContext.insert(session)
        try sourceContext.save()

        let backup = try ImportExportService.exportAllData(from: sourceContext)
        let destination = try makeContainer()
        _ = try ImportExportService.importData(backup, into: destination.mainContext)

        let restoredMeasurements = try destination.mainContext.fetch(FetchDescriptor<AuraHealth.Measurement>())
        let restoredConversations = try destination.mainContext.fetch(FetchDescriptor<Conversation>())
        let restoredDocuments = try destination.mainContext.fetch(FetchDescriptor<VaultDocument>())
        let restoredMemories = try destination.mainContext.fetch(FetchDescriptor<HealthMemory>())
        let restoredSessions = try destination.mainContext.fetch(FetchDescriptor<LabSession>())

        XCTAssertEqual(restoredMeasurements.map(\.id), [measurement.id])
        XCTAssertEqual(restoredConversations.map(\.id), [conversation.id])
        XCTAssertEqual(restoredDocuments.map(\.id), [document.id])
        XCTAssertEqual(restoredDocuments.first?.fileData, document.fileData)
        XCTAssertEqual(restoredMemories.map(\.id), [memory.id])
        XCTAssertEqual(restoredSessions.map(\.id), [session.id])
    }

    func testMergeImportDoesNotDuplicateExistingRecords() throws {
        let source = try makeContainer()
        source.mainContext.insert(AuraHealth.Measurement(metricType: .steps, value: 8_000))
        try source.mainContext.save()

        let backup = try ImportExportService.exportAllData(from: source.mainContext)
        let destination = try makeContainer()

        let first = try ImportExportService.importData(backup, into: destination.mainContext)
        let second = try ImportExportService.importData(backup, into: destination.mainContext)

        XCTAssertEqual(first.measurements, 1)
        XCTAssertEqual(second.total, 0)
        XCTAssertEqual(try destination.mainContext.fetchCount(FetchDescriptor<AuraHealth.Measurement>()), 1)
    }

    func testClearDatabaseRemovesEveryPersistedModel() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(AuraHealth.Measurement(metricType: .heartRate, value: 70))
        context.insert(Conversation(title: "Private chat"))
        context.insert(VaultDocument(title: "Private", fileName: "private.pdf", fileType: .pdf))
        context.insert(HealthMemory(content: "Private memory"))
        context.insert(LabSession(date: Date(), name: "Private lab"))
        context.insert(SmartHabit(name: "Legacy suggestion"))
        context.insert(ProtocolMeta())
        try context.save()

        try DataLifecycleService.clearDatabase(from: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AuraHealth.Measurement>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Conversation>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<VaultDocument>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<HealthMemory>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LabSession>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SmartHabit>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProtocolMeta>()), 0)
    }

    func testConditionLinksSurviveRoundTrip() throws {
        let source = try makeContainer()
        let context = source.mainContext
        let med = Medication(name: "Metformin", dosage: "500 mg")
        let habit = Habit(name: "Walk 10k Steps")
        let condition = Condition(name: "Pre-diabetes", status: .managed)
        condition.trackedMarkers = ["HbA1c"]
        condition.trackedMetrics = [MetricType.weight.rawValue]
        context.insert(med)
        context.insert(habit)
        context.insert(condition)
        condition.medications = [med]
        condition.habits = [habit]
        try context.save()

        let backup = try ImportExportService.exportAllData(from: context)
        let destination = try makeContainer()
        _ = try ImportExportService.importData(backup, into: destination.mainContext)

        let restored = try XCTUnwrap(try destination.mainContext.fetch(FetchDescriptor<Condition>()).first)
        XCTAssertEqual(restored.trackedMarkers, ["HbA1c"])
        XCTAssertEqual(restored.trackedMetrics, [MetricType.weight.rawValue])
        XCTAssertEqual(restored.medications?.map(\.id), [med.id])
        XCTAssertEqual(restored.habits?.map(\.id), [habit.id])
        XCTAssertEqual(restored.linkSummary, "1 lab · 1 vital · 1 med · 1 habit")
    }

    func testBackupFromBeforeConditionLinksStillImports() throws {
        let source = try makeContainer()
        source.mainContext.insert(Condition(name: "Asthma"))
        try source.mainContext.save()

        // Remove the link fields, as in a backup made by an older version
        let backup = try ImportExportService.exportAllData(from: source.mainContext)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: backup) as? [String: Any])
        var conditions = try XCTUnwrap(json["conditions"] as? [[String: Any]])
        for key in ["trackedMarkers", "trackedMetrics", "medicationIDs", "habitIDs"] {
            conditions = conditions.map { var c = $0; c.removeValue(forKey: key); return c }
        }
        json["conditions"] = conditions
        let oldBackup = try JSONSerialization.data(withJSONObject: json)

        let destination = try makeContainer()
        _ = try ImportExportService.importData(oldBackup, into: destination.mainContext)
        let restored = try destination.mainContext.fetch(FetchDescriptor<Condition>())
        XCTAssertEqual(restored.map(\.name), ["Asthma"])
        XCTAssertNil(restored.first?.linkSummary)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Measurement.self,
            Medication.self,
            MedicationLog.self,
            Biomarker.self,
            Habit.self,
            HabitLog.self,
            Condition.self,
            DietPlan.self,
            MetricRange.self,
            VaultDocument.self,
            HealthMemory.self,
            Conversation.self,
            SmartHabit.self,
            ProtocolMeta.self,
            LabSession.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

final class ConditionSuggestionsTests: XCTestCase {
    func testSuggestionsMatchCommonConditionNames() {
        XCTAssertEqual(ConditionSuggestions.suggestion(for: "Pre-diabetes")?.markers.first, "HbA1c")
        XCTAssertEqual(ConditionSuggestions.suggestion(for: "Mild Hypercholesterolemia")?.markers.first, "LDL Cholesterol")
        XCTAssertEqual(ConditionSuggestions.suggestion(for: "Hypertension")?.metrics, [.bloodPressure, .heartRate])
        XCTAssertNil(ConditionSuggestions.suggestion(for: "Seasonal allergies"))
    }

    func testMarkerAliasesCountAsTheSameTest() {
        XCTAssertTrue(ConditionSuggestions.sameMarker("Fasting Glucose", "Glucose"))
        XCTAssertTrue(ConditionSuggestions.sameMarker("ldl", "LDL Cholesterol"))
        XCTAssertFalse(ConditionSuggestions.sameMarker("HDL Cholesterol", "LDL Cholesterol"))
    }
}
