import Foundation
import SwiftData

/// Builds the app's `ModelContainer`s. No migration plan is passed — see CLAUDE.md.
nonisolated enum ModelContainerFactory {
    static let cloudKitContainerID = "iCloud.com.aurlaw.commonplace"

    /// The CloudKit-backed store. Only the running app calls this; tests and previews never do.
    static func makePersistent() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .private(cloudKitContainerID)
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// An in-memory store with CloudKit disabled, for tests and previews.
    static func makeInMemory() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
