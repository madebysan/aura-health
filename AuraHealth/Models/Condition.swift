import Foundation
import SwiftData

@Model
final class Condition {
    var id: UUID = UUID()
    var name: String = ""
    var status: ConditionStatus = ConditionStatus.active
    var diagnosedDate: Date?
    var notes: String = ""

    /// Meds and supplements taken for this condition (many-to-many).
    @Relationship(deleteRule: .nullify, inverse: \Medication.conditions)
    var medications: [Medication]?

    /// Habits kept for this condition (many-to-many).
    @Relationship(deleteRule: .nullify, inverse: \Habit.conditions)
    var habits: [Habit]?

    /// Lab markers watched for this condition, as `Biomarker.marker` names.
    var trackedMarkers: [String] = []

    /// Vitals watched for this condition, as `MetricType` raw values.
    var trackedMetrics: [String] = []

    init(
        name: String,
        status: ConditionStatus = .active,
        diagnosedDate: Date? = nil,
        notes: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.status = status
        self.diagnosedDate = diagnosedDate
        self.notes = notes
    }
}
