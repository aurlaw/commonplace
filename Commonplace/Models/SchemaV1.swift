import Foundation
import SwiftData

/// Version 1 of the data model, frozen as it shipped (I1–I15). The app runs on `SchemaV2`; this
/// copy exists so the migration test can create a real V1 store and open it with the current
/// schema. Never change it. See CLAUDE.md for the CloudKit model rules.
nonisolated enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Topic.self, Entry.self, Photo.self]
    }
}

extension SchemaV1 {
    @Model
    final class Topic {
        var title: String = ""
        var summary: String = ""
        var colorName: String = TopicColor.defaultColor.rawValue
        var isArchived: Bool = false
        var capturesLocation: Bool = false
        var createdAt: Date = Date.now
        var deletedAt: Date? = nil

        @Relationship(deleteRule: .cascade, inverse: \Entry.topic)
        var entries: [Entry]? = []

        init(title: String = "", createdAt: Date = .now) {
            self.title = title
            self.createdAt = createdAt
        }
    }

    @Model
    final class Entry {
        var date: Date = Date.now
        var createdAt: Date = Date.now
        var body: String = ""
        var deletedAt: Date? = nil
        var latitude: Double? = nil
        var longitude: Double? = nil
        var placeName: String? = nil
        var topic: Topic? = nil

        @Relationship(deleteRule: .cascade, inverse: \Photo.entry)
        var photos: [Photo]? = []

        init(body: String = "", date: Date = .now, topic: Topic? = nil, createdAt: Date = .now) {
            self.body = body
            self.date = date
            self.topic = topic
            self.createdAt = createdAt
        }
    }

    @Model
    final class Photo {
        @Attribute(.externalStorage)
        var imageData: Data? = nil
        var thumbnailData: Data? = nil
        var order: Int = 0
        var createdAt: Date = Date.now
        var entry: Entry? = nil

        init(
            imageData: Data? = nil, thumbnailData: Data? = nil, order: Int = 0,
            entry: Entry? = nil
        ) {
            self.imageData = imageData
            self.thumbnailData = thumbnailData
            self.order = order
            self.entry = entry
        }
    }
}
