import Foundation
import SwiftData
import Testing

@testable import Commonplace

/// A processor that returns fixed data, or fails, without touching ImageIO.
struct FakeImageProcessor: ImageProcessor {
    var result: Result<ProcessedImage, ImageProcessingError> = .success(
        ProcessedImage(image: Data("image".utf8), thumbnail: Data("thumb".utf8))
    )

    func process(_ data: Data) async throws -> ProcessedImage {
        try result.get()
    }
}

@MainActor
struct EntryDraftPhotoTests {
    private let container: ModelContainer
    private let context: ModelContext
    private let topic: Topic
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    init() throws {
        container = try ModelContainerFactory.makeInMemory()
        context = ModelContext(container)
        topic = Topic(title: "Sedona trip")
        context.insert(topic)
        try context.save()
    }

    // MARK: Validity

    @Test func isValidWithPhotosOnlyTextOnlyOrBoth() {
        var draft = EntryDraft(mode: .newInTopic(topic), now: now)
        #expect(!draft.isValid)  // neither

        draft.addPhoto(processed("a"))
        #expect(draft.isValid)  // photos only

        draft.body = "Cathedral Rock."
        #expect(draft.isValid)  // both

        draft.photos = []
        #expect(draft.isValid)  // text only

        draft.body = "   "
        #expect(!draft.isValid)
    }

    @Test func photosDoNotReplaceTheNeedForATopic() {
        var draft = EntryDraft(mode: .newFromList, now: now)
        draft.addPhoto(processed("a"))

        #expect(!draft.isValid)
    }

    // MARK: Adding, removing, and the limit

    @Test func addPhotoAppendsInPickOrder() {
        var draft = EntryDraft(mode: .newInTopic(topic), now: now)
        draft.addPhoto(processed("a"))
        draft.addPhoto(processed("b"))

        #expect(draft.photos.map(\.thumbnailData) == [Data("thumb-a".utf8), Data("thumb-b".utf8)])
        #expect(Set(draft.photos.map(\.id)).count == 2)
    }

    @Test func draftNeverHoldsMoreThanTwentyPhotos() {
        var draft = EntryDraft(mode: .newInTopic(topic), now: now)
        for index in 0..<20 {
            #expect(draft.remainingPhotoSlots == 20 - index)
            let added = draft.addPhoto(processed("\(index)"))
            #expect(added)
        }

        #expect(draft.remainingPhotoSlots == 0)
        let addedPastLimit = draft.addPhoto(processed("one too many"))
        #expect(!addedPastLimit)
        #expect(draft.photos.count == 20)
    }

    @Test func editDraftStartsWithTheEntrysPhotosInOrder() throws {
        let entry = try savedEntry(photoCount: 3)

        let draft = EntryDraft(mode: .edit(entry), now: now)

        #expect(
            draft.photos.map(\.id) == entry.sortedPhotos.map { .existing($0.persistentModelID) })
        #expect(draft.remainingPhotoSlots == 17)
    }

    // MARK: Dirty detection

    @Test func unchangedPhotosAreNotDirty() throws {
        let entry = try savedEntry(photoCount: 2)
        let original = EntryDraft(mode: .edit(entry), now: now)

        #expect(!original.isDirty(comparedTo: original))
        #expect(!EntryDraft(mode: .edit(entry), now: now).isDirty(comparedTo: original))
    }

    @Test func addingAPhotoIsDirty() throws {
        let entry = try savedEntry(photoCount: 2)
        let original = EntryDraft(mode: .edit(entry), now: now)
        var draft = original
        draft.addPhoto(processed("new"))

        #expect(draft.isDirty(comparedTo: original))
    }

    @Test func removingAPhotoIsDirty() throws {
        let entry = try savedEntry(photoCount: 2)
        let original = EntryDraft(mode: .edit(entry), now: now)
        var draft = original
        draft.removePhoto(draft.photos[0].id)

        #expect(draft.photos.count == 1)
        #expect(draft.isDirty(comparedTo: original))
    }

    @Test func addingThenRemovingTheSamePhotoIsNotDirty() {
        let original = EntryDraft(mode: .newInTopic(topic), now: now)
        var draft = original
        draft.addPhoto(processed("a"))
        draft.removePhoto(draft.photos[0].id)

        #expect(!draft.isDirty(comparedTo: original))
    }

    // MARK: Saving

    @Test func newEntryInsertsItsPhotosInOrder() throws {
        var draft = EntryDraft(mode: .newInTopic(topic), now: now)
        for name in ["a", "b", "c"] {
            draft.addPhoto(processed(name))
        }

        let entry = draft.makeEntry()
        context.insert(entry)
        draft.applyPhotos(to: entry, in: context)
        try context.save()

        let photos = entry.sortedPhotos
        #expect(photos.map(\.order) == [0, 1, 2])
        #expect(photos.map(\.imageData) == ["a", "b", "c"].map { Data("image-\($0)".utf8) })
        #expect(photos.map(\.thumbnailData) == ["a", "b", "c"].map { Data("thumb-\($0)".utf8) })
        #expect(photos.allSatisfy { $0.entry === entry })
        #expect(try context.fetchCount(FetchDescriptor<Photo>()) == 3)
        #expect(entry.body == "")
    }

    @Test func editRemovesDroppedPhotosInsertsNewOnesAndRewritesOrder() throws {
        let entry = try savedEntry(photoCount: 3)
        let before = entry.sortedPhotos
        var draft = EntryDraft(mode: .edit(entry), now: now)
        draft.removePhoto(draft.photos[0].id)
        draft.addPhoto(processed("new"))

        draft.applyPhotos(to: entry, in: context)
        try context.save()

        let after = entry.sortedPhotos
        #expect(after.count == 3)
        #expect(after.map(\.order) == [0, 1, 2])
        #expect(after[0] === before[1])
        #expect(after[1] === before[2])
        #expect(after[2].imageData == Data("image-new".utf8))
        // The dropped photo is gone from the store, not just from the entry.
        let stored = try context.fetch(FetchDescriptor<Photo>())
        #expect(stored.count == 3)
        #expect(!stored.contains { $0.imageData == Data("image-0".utf8) })
    }

    @Test func removingEveryPhotoLeavesNone() throws {
        let entry = try savedEntry(photoCount: 2)
        var draft = EntryDraft(mode: .edit(entry), now: now)
        draft.photos = []

        draft.applyPhotos(to: entry, in: context)
        try context.save()

        #expect(entry.sortedPhotos.isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<Photo>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Entry>()) == 1)
    }

    @Test func applyPhotosTouchesNothingElseOnTheEntry() throws {
        let entry = try savedEntry(photoCount: 1)
        let date = entry.date
        let createdAt = entry.createdAt
        entry.latitude = 34.8697
        entry.longitude = -111.7610
        entry.placeName = "Sedona, AZ"
        try context.save()

        var draft = EntryDraft(mode: .edit(entry), now: now)
        draft.body = "Changed in the draft only"
        draft.date = now.addingTimeInterval(-99)
        draft.photos = []
        draft.addPhoto(processed("new"))
        draft.applyPhotos(to: entry, in: context)
        try context.save()

        #expect(entry.body == "Entry text")
        #expect(entry.date == date)
        #expect(entry.createdAt == createdAt)
        #expect(entry.topic === topic)
        #expect(entry.latitude == 34.8697)
        #expect(entry.longitude == -111.7610)
        #expect(entry.placeName == "Sedona, AZ")
        #expect(entry.deletedAt == nil)
    }

    @Test func unchangedDraftLeavesPhotosAsTheyWere() throws {
        let entry = try savedEntry(photoCount: 3)
        let before = entry.sortedPhotos.map(\.persistentModelID)

        EntryDraft(mode: .edit(entry), now: now).applyPhotos(to: entry, in: context)
        #expect(!context.hasChanges)
        try context.save()

        #expect(entry.sortedPhotos.map(\.persistentModelID) == before)
    }

    // MARK: Rollback

    /// What `saveOrRollback()` does when the save fails: nothing added, nothing lost.
    @Test func rollbackLeavesNoNewPhotosAndRestoresRemovedOnes() throws {
        let entry = try savedEntry(photoCount: 2)
        let before = try context.fetch(FetchDescriptor<Photo>()).map(\.persistentModelID)
        var draft = EntryDraft(mode: .edit(entry), now: now)
        draft.removePhoto(draft.photos[0].id)
        draft.addPhoto(processed("new"))
        draft.body = "Edited"

        draft.apply(to: entry)
        draft.applyPhotos(to: entry, in: context)
        context.rollback()

        let after = try context.fetch(FetchDescriptor<Photo>())
        #expect(Set(after.map(\.persistentModelID)) == Set(before))
        #expect(!after.contains { $0.imageData == Data("image-new".utf8) })
        #expect(entry.sortedPhotos.map(\.order) == [0, 1])
        #expect(entry.body == "Entry text")
        // The draft is intact, so the sheet can stay open and the user can try again.
        #expect(draft.photos.count == 2)
        #expect(draft.body == "Edited")
    }

    @Test func rollbackOfANewEntryLeavesNothingBehind() throws {
        var draft = EntryDraft(mode: .newInTopic(topic), now: now)
        draft.addPhoto(processed("a"))
        draft.addPhoto(processed("b"))

        let entry = draft.makeEntry()
        context.insert(entry)
        draft.applyPhotos(to: entry, in: context)
        context.rollback()

        #expect(try context.fetchCount(FetchDescriptor<Entry>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Photo>()) == 0)
        #expect(topic.liveEntries.isEmpty)
    }

    // MARK: Fake processor

    @Test func fakeProcessorFeedsTheDraft() async throws {
        var draft = EntryDraft(mode: .newInTopic(topic), now: now)

        draft.addPhoto(try await FakeImageProcessor().process(Data()))

        #expect(draft.photos.map(\.thumbnailData) == [Data("thumb".utf8)])
        await #expect(throws: ImageProcessingError.undecodable) {
            try await FakeImageProcessor(result: .failure(.undecodable)).process(Data())
        }
    }

    // MARK: Helpers

    private func processed(_ name: String) -> ProcessedImage {
        ProcessedImage(image: Data("image-\(name)".utf8), thumbnail: Data("thumb-\(name)".utf8))
    }

    /// A saved entry in the topic with `photoCount` photos, `image-0` … in order.
    private func savedEntry(photoCount: Int) throws -> Entry {
        let entry = Entry(body: "Entry text", date: now.addingTimeInterval(-3_600), topic: topic)
        context.insert(entry)
        for order in 0..<photoCount {
            context.insert(
                Photo(
                    imageData: Data("image-\(order)".utf8),
                    thumbnailData: Data("thumb-\(order)".utf8),
                    order: order,
                    entry: entry
                )
            )
        }
        try context.save()
        return entry
    }
}
