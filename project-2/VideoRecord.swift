
import Foundation
import SwiftData

@Model
final class VideoRecord {
    var id: UUID
    var createdAt: Date
    var duration: TimeInterval
    var fileName: String
    var youtubeURL: String?

    init(id: UUID = UUID(), createdAt: Date = .now, duration: TimeInterval, fileName: String) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.fileName = fileName
    }
}
