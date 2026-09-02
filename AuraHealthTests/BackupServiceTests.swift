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
