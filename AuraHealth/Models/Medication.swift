import Foundation
import SwiftData

@Model
final class Medication {
    var id: UUID = UUID()
    var name: String = ""
    var dosage: String = ""
    var frequency: MedicationFrequency = MedicationFrequency.daily
    var condition: String = ""
    var type: MedicationType = MedicationType.rx
    var timing: MedicationTiming = MedicationTiming.anyTime
    var startDate: Date?
    var endDate: Date?
    var active: Bool = true
    var gridSection: GridSection = GridSection.morning
    var gridOrder: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \MedicationLog.medication)
    var logs: [MedicationLog]?

    init(
        name: String,
        dosage: String = "",
        frequency: MedicationFrequency = .daily,
        condition: String = "",
        type: MedicationType = .rx,
        timing: MedicationTiming = .anyTime,
        startDate: Date? = nil,
        endDate: Date? = nil,
        gridSection: GridSection = .morning,
        gridOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.dosage = dosage
        self.frequency = frequency
        self.condition = condition
        self.type = type
        self.timing = timing
        self.startDate = startDate
        self.endDate = endDate
        self.gridSection = gridSection
        self.gridOrder = gridOrder
    }
}
