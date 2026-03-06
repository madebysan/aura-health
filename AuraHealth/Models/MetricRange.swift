import Foundation
import SwiftData

@Model
final class MetricRange {
    var id: UUID = UUID()
    var metricType: MetricType = MetricType.weight
    var low: Double = 0
    var high: Double = 0

    init(metricType: MetricType, low: Double, high: Double) {
        self.id = UUID()
        self.metricType = metricType
        self.low = low
        self.high = high
    }
}
