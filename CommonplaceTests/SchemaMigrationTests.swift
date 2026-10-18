import Foundation
import SwiftData
import Testing

@testable import Commonplace

/// The one test with an on-disk store: a V1 store, as it exists on devices before I16, must open
/// with the current schema and no migration plan, with its data intact. CloudKit is disabled.
@MainActor
struct SchemaMigrationTests {
    @Test func aVersionOneStoreOpensWithTheCurrentSchema() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "SchemaMigrationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Commonplace.store")
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

        // Write with V1, then let the container go so the store is closed.
        do {
            let schema = Schema(versionedSchema: SchemaV1.self)
            let configuration = ModelConfiguration(
                schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            let topic = SchemaV1.Topic(title: "Sedona trip", createdAt: date)
            topic.capturesLocation = true
            context.insert(topic)
            let entry = SchemaV1.Entry(body: "Broken Arrow", date: date, topic: topic)
            entry.latitude = 34.84555
            entry.longitude = -111.75681
            entry.placeName = "Broken Arrow Trailhead"
            context.insert(entry)
            context.insert(
                SchemaV1.Photo(imageData: Data([1, 2, 3]), thumbnailData: Data([4]), entry: entry))
            try context.save()
        }

        // Reopen with the current schema, exactly as the app builds it: no migration plan.
        let schema = Schema(versionedSchema: SchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let topics = try context.fetch(FetchDescriptor<Topic>())
        #expect(topics.map(\.title) == ["Sedona trip"])
        let topic = try #require(topics.first)
        #expect(topic.capturesLocation)
        #expect(topic.createdAt == date)

        let entry = try #require(topic.entries?.first)
        #expect(entry.body == "Broken Arrow")
        #expect(entry.date == date)
        #expect(entry.latitude == 34.84555)
        #expect(entry.longitude == -111.75681)
        #expect(entry.placeName == "Broken Arrow Trailhead")
        #expect(entry.sortedPhotos.map(\.imageData) == [Data([1, 2, 3])])
        #expect(entry.sortedPhotos.map(\.thumbnailData) == [Data([4])])
        #expect(entry.route == nil)
        #expect(!entry.hasRoute)

        // The migrated store takes the new model.
        let route = Route(name: "Afternoon hike")
        context.insert(route)
        entry.route = route
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Route>()).first?.entry === entry)
    }
}
