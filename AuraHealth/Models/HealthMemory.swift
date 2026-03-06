import Foundation
import SwiftData

@Model
final class HealthMemory {
    var id: UUID = UUID()
    var content: String = ""
    var pinned: Bool = false
    var createdAt: Date = Date()

    init(content: String, pinned: Bool = false) {
        self.id = UUID()
        self.content = content
        self.pinned = pinned
        self.createdAt = Date()
    }
}
