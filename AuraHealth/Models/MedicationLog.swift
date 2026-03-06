import Foundation
import SwiftData

@Model
final class MedicationLog {
    var id: UUID = UUID()
    var date: Date = Date()
    var taken: Bool = false
    var dosage: String = ""
    var notes: String = ""

    var medication: Medication?

    init(
        date: Date = Date(),
        medication: Medication,
        taken: Bool,
        dosage: String = "",
        notes: String = ""
    ) {
        self.id = UUID()
        self.date = date
        self.medication = medication
        self.taken = taken
        self.dosage = dosage
        self.notes = notes
    }
}
