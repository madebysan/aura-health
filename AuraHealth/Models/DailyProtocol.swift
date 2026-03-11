import Foundation
import SwiftData

/// A single AI-generated daily action item.
/// Ephemeral — regenerated each day based on fresh health data.
@Model
final class SmartHabit {
    var id: UUID = UUID()
    var date: Date = Date()          // Which day this habit is for
    var name: String = ""            // "Walk 30 min after lunch"
    var reason: String = ""          // "Your HbA1c is 5.9% — post-meal walks lower glucose spikes"
    var gridSection: GridSection = GridSection.morning
    var done: Bool = false
    var dismissed: Bool = false      // User swiped to dismiss — don't show again today
    var priority: Int = 0            // Lower = more important (0 = top)

    init(
        date: Date = Date(),
        name: String,
        reason: String = "",
        gridSection: GridSection = .morning,
        priority: Int = 0
    ) {
        self.id = UUID()
        self.date = Calendar.current.startOfDay(for: date)
        self.name = name
        self.reason = reason
        self.gridSection = gridSection
        self.priority = priority
    }
}

/// Tracks when the protocol was last generated to avoid redundant API calls.
@Model
final class ProtocolMeta {
    var id: UUID = UUID()
    var generatedDate: Date = Date()   // When the protocol was generated
    var forDate: Date = Date()         // Which day it covers
    var contextHash: String = ""       // Hash of input data — regenerate if data changed

    init(forDate: Date = Date(), contextHash: String = "") {
        self.id = UUID()
        self.generatedDate = Date()
        self.forDate = Calendar.current.startOfDay(for: forDate)
        self.contextHash = contextHash
    }
}
