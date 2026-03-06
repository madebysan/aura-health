import Foundation
import SwiftData

@Model
final class Habit {
    var id: UUID = UUID()
    var name: String = ""
    var category: HabitCategory = HabitCategory.lifestyle
    var trackingType: TrackingType = TrackingType.boolean
    var frequency: String = "daily"
    var unit: String = "" // For quantity tracking (cups, drinks, mins, etc.)
    var active: Bool = true
    var gridSection: GridSection = GridSection.morning
    var gridOrder: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \HabitLog.habit)
    var logs: [HabitLog] = []

    init(
        name: String,
        category: HabitCategory = .lifestyle,
        trackingType: TrackingType = .boolean,
        frequency: String = "daily",
        unit: String = "",
        gridSection: GridSection = .morning,
        gridOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.category = category
        self.trackingType = trackingType
        self.frequency = frequency
        self.unit = unit
        self.gridSection = gridSection
        self.gridOrder = gridOrder
    }
}
