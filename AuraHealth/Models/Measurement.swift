import Foundation
import SwiftData

@Model
final class Measurement {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var metricType: MetricType = MetricType.weight
    var value: Double = 0
    var value2: Double? // Secondary value (e.g., diastolic BP)
    var unit: String = ""
    var source: MeasurementSource = MeasurementSource.manual
    var notes: String = ""

    init(
        timestamp: Date = Date(),
        metricType: MetricType,
        value: Double,
        value2: Double? = nil,
        unit: String? = nil,
        source: MeasurementSource = .manual,
        notes: String = ""
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.metricType = metricType
        self.value = value
        self.value2 = value2
        self.unit = unit ?? metricType.unit
        self.source = source
        self.notes = notes
    }

    /// Formatted display value (e.g., "120/80" for BP, "72" for HR)
    var displayValue: String {
        if metricType == .bloodPressure, let diastolic = value2 {
            return "\(Int(value))/\(Int(diastolic))"
        }
        if value == value.rounded() {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }
}
