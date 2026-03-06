import Foundation
import SwiftData

@Model
final class Conversation {
    var id: UUID = UUID()
    var title: String = ""
    var messagesData: Data? // Encoded [ChatMessage]
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var messages: [ChatMessage] {
        get {
            guard let data = messagesData else { return [] }
            return (try? JSONDecoder().decode([ChatMessage].self, from: data)) ?? []
        }
        set {
            messagesData = try? JSONEncoder().encode(newValue)
            updatedAt = Date()
        }
    }

    init(title: String = "New Chat") {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    func addMessage(role: ChatRole, content: String) {
        var current = messages
        current.append(ChatMessage(role: role, content: content))
        messages = current
    }
}
