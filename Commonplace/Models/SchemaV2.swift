import Foundation
import SwiftData

/// Version 2 of the data model: V1 plus `Route` and the optional `Entry.route` (I16). The change
/// is additive, so no migration plan is passed: SwiftData migrates a V1 store on open, which
/// `SchemaMigrationTests` proves. See CLAUDE.md for the CloudKit model rules every model follows.
nonisolated enum SchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Topic.self, Entry.self, Photo.self, Route.self]
    }
}

typealias Topic = SchemaV2.Topic
typealias Entry = SchemaV2.Entry
typealias Photo = SchemaV2.Photo
typealias Route = SchemaV2.Route
