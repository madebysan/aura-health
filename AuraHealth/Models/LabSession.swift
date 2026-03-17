import Foundation
import SwiftData

@Model
final class LabSession {
    var id: UUID = UUID()
    var date: Date = Date()
    var name: String = ""
    var notes: String = ""

    init(date: Date, name: String = "", notes: String = "") {
        self.id = UUID()
        self.date = date
        self.name = name
        self.notes = notes
    }
}
