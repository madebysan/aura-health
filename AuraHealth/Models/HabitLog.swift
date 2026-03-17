import Foundation
import SwiftData

@Model
final class HabitLog {
    var id: UUID = UUID()
    var date: Date = Date()
    var done: Bool = false
    var quantity: Double?
    var unit: String = ""
    var notes: String = ""

    var habit: Habit?

    init(
        date: Date = Date(),
        habit: Habit? = nil,
        done: Bool,
        quantity: Double? = nil,
        unit: String = "",
        notes: String = ""
    ) {
        self.id = UUID()
        self.date = date
        self.habit = habit
        self.done = done
        self.quantity = quantity
        self.unit = unit
        self.notes = notes
    }
}
