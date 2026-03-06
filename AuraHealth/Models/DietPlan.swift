import Foundation
import SwiftData

@Model
final class DietPlan {
    var id: UUID = UUID()
    var name: String = ""
    var dietType: String = "" // Template identifier
    var startDate: Date?
    var endDate: Date?
    var allowedFoods: [String] = []
    var avoidFoods: [String] = []
    var foodCategories: [String] = [] // Tracked food categories
    var active: Bool = true
    var notes: String = ""

    init(
        name: String,
        dietType: String = "",
        startDate: Date? = nil,
        endDate: Date? = nil,
        allowedFoods: [String] = [],
        avoidFoods: [String] = [],
        foodCategories: [String] = [],
        notes: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.dietType = dietType
        self.startDate = startDate
        self.endDate = endDate
        self.allowedFoods = allowedFoods
        self.avoidFoods = avoidFoods
        self.foodCategories = foodCategories
        self.notes = notes
    }
}
