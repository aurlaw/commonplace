import Foundation
import SwiftData
import Testing

@testable import Commonplace

// `makePersistent()` is deliberately not exercised: tests never create the CloudKit store.
struct ModelContainerFactoryTests {
    @Test func inMemoryContainerHasCloudKitDisabled() throws {
        let container = try ModelContainerFactory.makeInMemory()

        #expect(container.configurations.count == 1)
        for configuration in container.configurations {
            #expect(configuration.isStoredInMemoryOnly)
            #expect(configuration.cloudKitContainerIdentifier == nil)
        }
    }

    @Test func inMemoryContainerUsesSchemaV1() throws {
        let container = try ModelContainerFactory.makeInMemory()

        let entityNames = Set(container.schema.entities.map(\.name))
        #expect(entityNames == ["Topic", "Entry", "Photo"])
    }

    /// `CommonplaceApp` relies on this variable to pick the in-memory container under tests.
    @Test func hostAppCanDetectTestRun() {
        #expect(ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil)
    }

    @Test func cloudKitContainerIDMatchesEntitlement() {
        #expect(ModelContainerFactory.cloudKitContainerID == "iCloud.com.aurlaw.commonplace")
    }
}
