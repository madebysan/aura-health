import Foundation
import SwiftData

@Model
final class VaultDocument {
    var id: UUID = UUID()
    var title: String = ""
    var fileName: String = ""
    var fileType: VaultFileType = VaultFileType.pdf
    var mimeType: String = ""
    @Attribute(.externalStorage) var fileData: Data?
    var fileSize: Int = 0
    var tags: [String] = []
    var date: Date? // Document date (not upload date)
    var uploadedAt: Date = Date()
    var notes: String = ""

    init(
        title: String,
        fileName: String,
        fileType: VaultFileType,
        mimeType: String = "",
        fileData: Data? = nil,
        fileSize: Int = 0,
        tags: [String] = [],
        date: Date? = nil,
        notes: String = ""
    ) {
        self.id = UUID()
        self.title = title
        self.fileName = fileName
        self.fileType = fileType
        self.mimeType = mimeType
        self.fileData = fileData
        self.fileSize = fileSize
        self.tags = tags
        self.date = date
        self.uploadedAt = Date()
        self.notes = notes
    }
}
