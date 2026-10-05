import Foundation
import SwiftData

/// Version 1 of the data model. See CLAUDE.md for the CloudKit model rules every model follows.
nonisolated enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Topic.self, Entry.self, Photo.self]
    }
}

typealias Topic = SchemaV1.Topic
typealias Entry = SchemaV1.Entry
typealias Photo = SchemaV1.Photo
