import XCTest
@testable import AuraHealth

final class VitalsSummaryTests: XCTestCase {
    private let now = Date()
    private func daysAgo(_ days: Int) -> Date { Calendar.current.date(byAdding: .day, value: -days, to: now)! }

    func testOnlyCurrentOutOfRangeReadingsFlag() {
        let readings: [MetricType: AuraHealth.Measurement] = [
            .heartRate: AuraHealth.Measurement(timestamp: daysAgo(1), metricType: .heartRate, value: 104),
            .sleepDuration: AuraHealth.Measurement(timestamp: daysAgo(0), metricType: .sleepDuration, value: 5.1),
            .weight: AuraHealth.Measurement(timestamp: daysAgo(0), metricType: .weight, value: 81.8),
            // Out of range but older than a week: shown as "last logged", never flagged
            .spo2: AuraHealth.Measurement(timestamp: daysAgo(10), metricType: .spo2, value: 91),
        ]
        let flags = VitalsSummary.flags(order: [.heartRate, .sleepDuration, .weight, .spo2], latest: { readings[$0] }, now: now)
        XCTAssertEqual(flags, [
            VitalsSummary.Flag(metric: .heartRate, position: .above),
            VitalsSummary.Flag(metric: .sleepDuration, position: .below),
        ])
    }

    func testSentenceNamesFlagsInPlainLanguage() {
        let flags: [VitalsSummary.Flag] = [
            .init(metric: .bloodPressure, position: .above),
            VitalsSummary.Flag(metric: .heartRate, position: .above),
            VitalsSummary.Flag(metric: .sleepDuration, position: .below),
        ]
        XCTAssertEqual(VitalsSummary.sentence(flags: flags, hasReadings: true),
                       "Blood pressure and heart rate are above your typical range, and sleep duration is below it.")
        XCTAssertEqual(VitalsSummary.sentence(flags: [.init(metric: .hrv, position: .below)], hasReadings: true),
                       "HRV is below your typical range.")
    }

    func testSentenceForNoFlagsAndNoData() {
        XCTAssertEqual(VitalsSummary.sentence(flags: [], hasReadings: true), "Everything is within your typical range.")
        XCTAssertEqual(VitalsSummary.sentence(flags: [], hasReadings: false), "No readings yet. Connect Apple Health or add a measurement.")
    }

    func testNamesKeepAcronyms() {
        XCTAssertEqual(VitalsSummary.name(.spo2), "SpO2")
        XCTAssertEqual(VitalsSummary.name(.bloodPressure), "blood pressure")
    }

    func testMetricsLeaveTheListAfterThirtyDays() {
        let recent = AuraHealth.Measurement(timestamp: daysAgo(29), metricType: .weight, value: 80)
        let old = AuraHealth.Measurement(timestamp: daysAgo(31), metricType: .weight, value: 80)
        XCTAssertTrue(VitalsSummary.isWithin(days: VitalsSummary.visibleDays, of: recent, now: now))
        XCTAssertFalse(VitalsSummary.isWithin(days: VitalsSummary.visibleDays, of: old, now: now))
        XCTAssertFalse(VitalsSummary.isWithin(days: VitalsSummary.visibleDays, of: nil, now: now))
    }

    func testStatusMatchesTheShownNumber() {
        // 6.96 h displays as "7.0", which is inside 7–9 h
        XCTAssertEqual(MetricType.sleepDuration.rangePosition(of: 6.96), .within)
        XCTAssertEqual(MetricType.sleepDuration.rangePosition(of: 6.94), .below)
        // Blood pressure shows whole numbers: 120.4 displays as 120, inside 90–120
        XCTAssertEqual(MetricType.bloodPressure.rangePosition(of: 120.4), .within)
    }
}
