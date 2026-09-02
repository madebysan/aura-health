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
}
