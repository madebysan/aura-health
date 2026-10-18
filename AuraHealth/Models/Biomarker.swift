import Foundation
import SwiftData

@Model
final class Biomarker {
    var id: UUID = UUID()
    var testDate: Date = Date()
    var marker: String = ""
    var value: Double = 0
    var unit: String = ""
    var refMin: Double?
    var refMax: Double?
    var targetMin: Double? // User-defined personal target
    var targetMax: Double?
    var lab: String = ""
    var notes: String = ""

    init(
        testDate: Date = Date(),
        marker: String,
        value: Double,
        unit: String = "",
        refMin: Double? = nil,
        refMax: Double? = nil,
        targetMin: Double? = nil,
        targetMax: Double? = nil,
        lab: String = "",
        notes: String = ""
    ) {
        self.id = UUID()
        self.testDate = testDate
        self.marker = marker
        self.value = value
        self.unit = unit
        self.refMin = refMin
        self.refMax = refMax
        self.targetMin = targetMin
        self.targetMax = targetMax
        self.lab = lab
        self.notes = notes
    }

    /// Lower reference limit. Labs write upper-only ranges ("under 100") as a
    /// minimum of 0, so a minimum of 0 or less means there is no lower limit.
    var lowerLimit: Double? {
        guard let refMin, refMin > 0 else { return nil }
        return refMin
    }

    /// Upper reference limit, if the lab gave one.
    var upperLimit: Double? { refMax }

    /// Status based on reference range
    var status: BiomarkerStatus {
        let low = lowerLimit
        let high = upperLimit
        guard low != nil || high != nil else { return .unknown }
        if let low, value < low { return .abnormal }
        if let high, value > high { return .abnormal }
        if let low, value < low + borderlineMargin { return .borderline }
        if let high, value > high - borderlineMargin { return .borderline }
        return .normal
    }

    /// Where the value sits against the reference range.
    var rangePosition: RangePosition {
        if let low = lowerLimit, value < low { return .below }
        if let high = upperLimit, value > high { return .above }
        return lowerLimit == nil && upperLimit == nil ? .unknown : .within
    }

    /// Short, direction-aware label: "In range", "Near limit", "Above range"...
    var statusLabel: String {
        switch status {
        case .normal: "In range"
        case .borderline: "Near limit"
        case .abnormal: rangePosition == .below ? "Below range" : "Above range"
        case .unknown: "No range"
        }
    }

    /// True when the value is outside the range by no more than the borderline
    /// margin, such as LDL 102 against "under 100". Shown with a softer color.
    var isMarginallyOutOfRange: Bool {
        if let low = lowerLimit, value < low { return low - value <= borderlineMargin }
        if let high = upperLimit, value > high { return value - high <= borderlineMargin }
        return false
    }

    /// 10% of the range width, or of the single limit for one-sided ranges.
    private var borderlineMargin: Double {
        if let low = lowerLimit, let high = upperLimit { return (high - low) * 0.1 }
        return abs(lowerLimit ?? upperLimit ?? 0) * 0.1
    }
}

enum RangePosition {
    case below, within, above, unknown
}

enum BiomarkerStatus: String {
    case normal
    case borderline
    case abnormal
    case unknown

    var displayName: String {
        switch self {
        case .normal: "In range"
        case .borderline: "Near limit"
        case .abnormal: "Out of range"
        case .unknown: "No range"
        }
    }

    var colorName: String {
        switch self {
        case .normal: "green"
        case .borderline: "orange"
        case .abnormal: "red"
        case .unknown: "gray"
        }
    }
}
