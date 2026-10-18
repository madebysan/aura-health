import XCTest
import SwiftData
@testable import AuraHealth

@MainActor
final class StorageTests: XCTestCase {
    func testLocalContainerPersistsRecordsForItsLifetime() throws {
        let container = try AuraStorage.makeContainer(isStoredInMemoryOnly: true)
        let measurement = AuraHealth.Measurement(metricType: .heartRate, value: 72)
        container.mainContext.insert(measurement)
        try container.mainContext.save()

        let records = try container.mainContext.fetch(FetchDescriptor<AuraHealth.Measurement>())
        XCTAssertEqual(records.map(\.id), [measurement.id])
    }

    /// Apple Health vitals synced first must not stop the rest of the sample data.
    func testSampleDataFillsOtherAreasWhenVitalsAlreadyExist() throws {
        let container = try AuraStorage.makeContainer(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(AuraHealth.Measurement(metricType: .heartRate, value: 64))
        try context.save()

        SampleDataService.loadSampleData(into: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AuraHealth.Measurement>()), 1, "existing vitals are left alone")
        XCTAssertGreaterThan(try context.fetchCount(FetchDescriptor<Habit>()), 0)
        XCTAssertGreaterThan(try context.fetchCount(FetchDescriptor<Biomarker>()), 0)
        XCTAssertGreaterThan(try context.fetchCount(FetchDescriptor<Condition>()), 0)
        XCTAssertGreaterThan(try context.fetchCount(FetchDescriptor<DietPlan>()), 0)
        XCTAssertGreaterThan(try context.fetchCount(FetchDescriptor<Conversation>()), 0)

        // A second load adds nothing new
        let habits = try context.fetchCount(FetchDescriptor<Habit>())
        SampleDataService.loadSampleData(into: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Habit>()), habits)
    }

    /// Sample conditions come linked, so the condition page has something to show.
    func testSampleConditionsAreLinkedToTheirRecords() throws {
        let container = try AuraStorage.makeContainer(isStoredInMemoryOnly: true)
        let context = container.mainContext
        SampleDataService.loadSampleData(into: context)

        let conditions = try context.fetch(FetchDescriptor<Condition>())
        let prediabetes = try XCTUnwrap(conditions.first { $0.name == "Pre-diabetes" })
        XCTAssertEqual(prediabetes.trackedMarkers, ["HbA1c", "Fasting Glucose"])
        XCTAssertEqual(prediabetes.linkedMedications.map(\.name), ["Metformin"])
        XCTAssertEqual(prediabetes.linkedHabits.map(\.name), ["No Alcohol", "Walk 10k Steps"])
        XCTAssertNotNil(try context.fetch(FetchDescriptor<Biomarker>()).first { ConditionSuggestions.sameMarker($0.marker, "Fasting Glucose") })
    }
}
