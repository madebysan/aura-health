import XCTest
@testable import AuraHealth

final class BiomarkerStatusTests: XCTestCase {
    func testUpperOnlyRangeHasNoLowerLimit() {
        // LDL is written as 0–100, meaning "under 100"
        let low = Biomarker(marker: "LDL Cholesterol", value: 5, refMin: 0, refMax: 100)
        XCTAssertNil(low.lowerLimit)
        XCTAssertEqual(low.status, .normal)
        XCTAssertEqual(low.statusLabel, "In range")
    }

    func testSlightlyAboveUpperLimitIsMarginal() {
        let ldl = Biomarker(marker: "LDL Cholesterol", value: 102, refMin: 0, refMax: 100)
        XCTAssertEqual(ldl.status, .abnormal)
        XCTAssertEqual(ldl.rangePosition, .above)
        XCTAssertEqual(ldl.statusLabel, "Above range")
        XCTAssertTrue(ldl.isMarginallyOutOfRange)
    }

    func testClearlyBelowRangeIsNotMarginal() {
        let vitaminD = Biomarker(marker: "Vitamin D", value: 12, refMin: 30, refMax: 100)
        XCTAssertEqual(vitaminD.rangePosition, .below)
        XCTAssertEqual(vitaminD.statusLabel, "Below range")
        XCTAssertFalse(vitaminD.isMarginallyOutOfRange)
    }

    func testNearEitherEdgeOfTwoSidedRangeIsBorderline() {
        XCTAssertEqual(Biomarker(marker: "TSH", value: 0.6, refMin: 0.4, refMax: 4.0).status, .borderline)
        XCTAssertEqual(Biomarker(marker: "TSH", value: 3.8, refMin: 0.4, refMax: 4.0).status, .borderline)
        XCTAssertEqual(Biomarker(marker: "TSH", value: 2.0, refMin: 0.4, refMax: 4.0).status, .normal)
    }

    func testLowerOnlyRange() {
        let hdl = Biomarker(marker: "HDL Cholesterol", value: 38, refMin: 40, refMax: nil)
        XCTAssertEqual(hdl.status, .abnormal)
        XCTAssertEqual(hdl.statusLabel, "Below range")
    }

    func testNoRangeIsUnknown() {
        let marker = Biomarker(marker: "Custom", value: 1)
        XCTAssertEqual(marker.status, .unknown)
        XCTAssertEqual(marker.rangePosition, .unknown)
    }

    func testRangeFormatting() {
        XCTAssertEqual(AppFormat.range(low: nil, high: 100, unit: "mg/dL"), "under 100 mg/dL")
        XCTAssertEqual(AppFormat.range(low: 40, high: nil, unit: "mg/dL"), "over 40 mg/dL")
        XCTAssertEqual(AppFormat.range(low: 0.4, high: 4, unit: ""), "0.4–4")
    }

    func testChartDirection() {
        XCTAssertEqual(ChartSummary.direction(from: 138, to: 102), "Trending down")
        XCTAssertEqual(ChartSummary.direction(from: 100, to: 101), "Steady")
    }
}
