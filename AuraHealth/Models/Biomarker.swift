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

    /// Status based on reference range
    var status: BiomarkerStatus {
        guard let min = refMin, let max = refMax else { return .unknown }
        if value < min || value > max { return .abnormal }
        let range = max - min
        let lowerBorder = min + range * 0.1
        let upperBorder = max - range * 0.1
        if value < lowerBorder || value > upperBorder { return .borderline }
        return .normal
    }
}

enum BiomarkerStatus: String {
    case normal
    case borderline
    case abnormal
    case unknown

    var displayName: String {
        switch self {
        case .normal: "Normal"
        case .borderline: "Borderline"
        case .abnormal: "Abnormal"
        case .unknown: "Unknown"
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
