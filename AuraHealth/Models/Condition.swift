import Foundation
import SwiftData

@Model
final class Condition {
    var id: UUID = UUID()
    var name: String = ""
    var status: ConditionStatus = ConditionStatus.active
    var diagnosedDate: Date?
    var notes: String = ""

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
