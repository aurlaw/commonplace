import Foundation
import SwiftData
import Testing

@testable import Commonplace

/// Each test builds its own in-memory container, so nothing is shared between tests.
@MainActor
struct ModelTests {
    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        container = try ModelContainerFactory.makeInMemory()
        context = ModelContext(container)
    }

    // MARK: Defaults

    @Test func topicInsertsWithDocumentedDefaults() throws {
        let before = Date.now
        context.insert(Topic())
        try context.save()

        let topic = try #require(try context.fetch(FetchDescriptor<Topic>()).first)
        #expect(topic.title == "")
        #expect(topic.summary == "")
        #expect(topic.colorName == TopicColor.defaultColor.rawValue)
        #expect(topic.color == .indigo)
        #expect(topic.isArchived == false)
        #expect(topic.createdAt >= before)
        #expect(topic.deletedAt == nil)
        #expect(topic.isTrashed == false)
        #expect(topic.entries?.isEmpty == true)
    }

    @Test func entryInsertsWithDocumentedDefaults() throws {
        let before = Date.now
        context.insert(Entry())
        try context.save()

        let entry = try #require(try context.fetch(FetchDescriptor<Entry>()).first)
        #expect(entry.body == "")
        #expect(entry.date >= before)
        #expect(entry.createdAt >= before)
        #expect(entry.deletedAt == nil)
        #expect(entry.isTrashed == false)
        #expect(entry.topic == nil)
        #expect(entry.photos?.isEmpty == true)
    }

    @Test func photoInsertsWithDocumentedDefaults() throws {
        let before = Date.now
        context.insert(Photo())
        try context.save()

        let photo = try #require(try context.fetch(FetchDescriptor<Photo>()).first)
        #expect(photo.imageData == nil)
        #expect(photo.thumbnailData == nil)
        #expect(photo.order == 0)
        #expect(photo.createdAt >= before)
        #expect(photo.entry == nil)
    }

    // MARK: Location fields

    @Test func newTopicDoesNotCaptureLocation() throws {
        context.insert(Topic())
        try context.save()

        let topic = try #require(try context.fetch(FetchDescriptor<Topic>()).first)
        #expect(topic.capturesLocation == false)
    }

    @Test func newEntryHasNoLocation() throws {
        context.insert(Entry())
        try context.save()

        let entry = try #require(try context.fetch(FetchDescriptor<Entry>()).first)
        #expect(entry.latitude == nil)
        #expect(entry.longitude == nil)
        #expect(entry.placeName == nil)
        #expect(entry.hasLocation == false)
    }

    @Test func hasLocationNeedsBothCoordinates() {
        let entry = Entry()
        context.insert(entry)

        entry.latitude = 34.8697
        #expect(entry.hasLocation == false)

        entry.latitude = nil
        entry.longitude = -111.7610
        #expect(entry.hasLocation == false)

        entry.latitude = 34.8697
        #expect(entry.hasLocation)

        // A place name alone is not a location, and a location needs no place name.
        #expect(entry.placeName == nil)
        entry.latitude = nil
        entry.longitude = nil
        entry.placeName = "Sedona, AZ"
        #expect(entry.hasLocation == false)
    }

    // MARK: Relationships

    @Test func topicAndEntryLinkWhenSetFromEntrySide() throws {
        let topic = Topic(title: "Cigars")
        let entry = Entry(body: "First")
        context.insert(topic)
        context.insert(entry)

        entry.topic = topic
        try context.save()

        #expect(topic.entries?.map(\.persistentModelID) == [entry.persistentModelID])
    }

    @Test func topicAndEntryLinkWhenSetFromTopicSide() throws {
        let topic = Topic(title: "Cigars")
        let entry = Entry(body: "First")
        context.insert(topic)
        context.insert(entry)

        topic.entries?.append(entry)
        try context.save()

        #expect(entry.topic?.persistentModelID == topic.persistentModelID)
    }

    @Test func entryAndPhotoLinkWhenSetFromPhotoSide() throws {
        let entry = Entry()
        let photo = Photo()
        context.insert(entry)
        context.insert(photo)

        photo.entry = entry
        try context.save()

        #expect(entry.photos?.map(\.persistentModelID) == [photo.persistentModelID])
    }

    @Test func entryAndPhotoLinkWhenSetFromEntrySide() throws {
        let entry = Entry()
        let photo = Photo()
        context.insert(entry)
        context.insert(photo)

        entry.photos?.append(photo)
        try context.save()

        #expect(photo.entry?.persistentModelID == entry.persistentModelID)
    }

    // MARK: Deletion

    @Test func permanentDeleteCascadesToEntriesAndPhotos() throws {
        let topic = try insertTopicWithEntriesAndPhotos()
        let other = Entry(body: "Unrelated")
        context.insert(other)
        try context.save()

        context.delete(topic)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<Topic>()) == 0)
        #expect(try context.fetch(FetchDescriptor<Entry>()).map(\.body) == ["Unrelated"])
        #expect(try context.fetchCount(FetchDescriptor<Photo>()) == 0)
    }

    @Test func softDeleteKeepsObjectAndChildren() throws {
        let topic = try insertTopicWithEntriesAndPhotos()

        topic.deletedAt = .now
        try context.save()

        #expect(topic.isTrashed)
        #expect(try context.fetchCount(FetchDescriptor<Topic>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Entry>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<Photo>()) == 4)
    }

    @Test func fetchFilteringDeletedAtExcludesSoftDeletedTopicsAndEntries() throws {
        let kept = Topic(title: "Kept")
        let trashed = Topic(title: "Trashed")
        let keptEntry = Entry(body: "Kept", topic: kept)
        let trashedEntry = Entry(body: "Trashed", topic: kept)
        for model in [kept, trashed] { context.insert(model) }
        for model in [keptEntry, trashedEntry] { context.insert(model) }
        trashed.deletedAt = .now
        trashedEntry.deletedAt = .now
        try context.save()

        let topics = try context.fetch(
            FetchDescriptor<Topic>(predicate: #Predicate { $0.deletedAt == nil })
        )
        let entries = try context.fetch(
            FetchDescriptor<Entry>(predicate: #Predicate { $0.deletedAt == nil })
        )

        #expect(topics.map(\.title) == ["Kept"])
        #expect(entries.map(\.body) == ["Kept"])
    }

    // MARK: Computed properties

    @Test func sortedPhotosOrdersByOrderThenCreatedAt() throws {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let entry = Entry()
        context.insert(entry)
        let photos = [
            Photo(order: 1, entry: entry, createdAt: base.addingTimeInterval(20)),
            Photo(order: 0, entry: entry, createdAt: base.addingTimeInterval(30)),
            Photo(order: 1, entry: entry, createdAt: base.addingTimeInterval(10)),
            Photo(order: 0, entry: entry, createdAt: base.addingTimeInterval(5)),
        ]
        for photo in photos { context.insert(photo) }
        try context.save()

        let sorted = entry.sortedPhotos
        #expect(sorted.map(\.order) == [0, 0, 1, 1])
        #expect(sorted.map { $0.createdAt.timeIntervalSince(base) } == [5, 30, 10, 20])
    }

    @Test func topicColorRoundTripsThroughColorName() throws {
        let topic = Topic(color: .teal)
        context.insert(topic)
        #expect(topic.colorName == "teal")

        topic.color = .purple
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<Topic>()).first)
        #expect(fetched.colorName == "purple")
        #expect(fetched.color == .purple)
    }

    @Test func topicColorFallsBackToDefaultForUnknownRawValue() {
        let topic = Topic()
        context.insert(topic)

        topic.colorName = "chartreuse"

        #expect(topic.color == .indigo)
    }

    // MARK: External storage

    @Test func imageDataStoresAndReadsBackLargeBlob() throws {
        let blob = Data((0..<2_000_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        context.insert(Photo(imageData: blob))
        try context.save()

        // A fresh context has no cached instance, so the value is read from the store.
        let freshContext = ModelContext(container)
        let photo = try #require(try freshContext.fetch(FetchDescriptor<Photo>()).first)
        #expect(photo.imageData == blob)
    }

    // MARK: Helpers

    /// One topic with two entries, each with two photos.
    private func insertTopicWithEntriesAndPhotos() throws -> Topic {
        let topic = Topic(title: "Sedona trip")
        context.insert(topic)
        for index in 0..<2 {
            let entry = Entry(body: "Entry \(index)", topic: topic)
            context.insert(entry)
            for order in 0..<2 {
                context.insert(Photo(order: order, entry: entry))
            }
        }
        try context.save()
        return topic
    }
}
