import Foundation
import SwiftData
import Testing

@testable import Commonplace

struct TrashRetentionTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func rawValuesRoundTrip() {
        for retention in TrashRetention.allCases {
            #expect(TrashRetention(storedValue: retention.rawValue) == retention)
        }
        #expect(TrashRetention.allCases.map(\.rawValue) == ["thirtyDays", "ninetyDays", "never"])
    }

    @Test func unknownStoredValueFallsBackToThirtyDays() {
        #expect(TrashRetention.defaultValue == .thirtyDays)
        #expect(TrashRetention(storedValue: "sevenDays") == .thirtyDays)
        #expect(TrashRetention(storedValue: "") == .thirtyDays)
    }

    @Test func cutoffIsTheRetentionPeriodBeforeNow() {
        #expect(
            TrashRetention.thirtyDays.cutoff(before: now) == now.addingTimeInterval(-30 * 86_400))
        #expect(
            TrashRetention.ninetyDays.cutoff(before: now) == now.addingTimeInterval(-90 * 86_400))
        #expect(TrashRetention.never.cutoff(before: now) == nil)
    }

    @Test func shorteningIsDetected() {
        #expect(TrashRetention.ninetyDays.isShortened(by: .thirtyDays))
        #expect(TrashRetention.never.isShortened(by: .ninetyDays))
        #expect(TrashRetention.never.isShortened(by: .thirtyDays))
        #expect(!TrashRetention.thirtyDays.isShortened(by: .ninetyDays))
        #expect(!TrashRetention.thirtyDays.isShortened(by: .never))
        #expect(!TrashRetention.thirtyDays.isShortened(by: .thirtyDays))
    }

    @Test func footerNamesTheRetention() {
        #expect(
            TrashRetention.thirtyDays.footer == "Items are deleted automatically after 30 days.")
        #expect(
            TrashRetention.ninetyDays.footer == "Items are deleted automatically after 90 days.")
        #expect(TrashRetention.never.footer == "Items are kept until you delete them.")
    }

    @Test func purgeIsDueAtMostOnceADay() {
        #expect(TrashRetention.isPurgeDue(lastPurge: nil, now: now))
        #expect(!TrashRetention.isPurgeDue(lastPurge: now, now: now))
        #expect(!TrashRetention.isPurgeDue(lastPurge: now.addingTimeInterval(-86_399), now: now))
        #expect(TrashRetention.isPurgeDue(lastPurge: now.addingTimeInterval(-86_400), now: now))
    }
}

@MainActor
struct TrashOperationsTests {
    private let container: ModelContainer
    private let context: ModelContext
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let trash: TrashOperations

    init() throws {
        container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        self.context = context
        let now = now
        trash = TrashOperations(context: context, now: { now })
    }

    // MARK: Move to Trash and restore

    @Test func trashingATopicStampsOnlyTheTopic() throws {
        let topic = try topic("Sedona trip", entries: 3, photosEach: 1)

        #expect(trash.moveToTrash(topic) == nil)

        #expect(topic.deletedAt == now)
        #expect(topic.isTrashed)
        #expect((topic.entries ?? []).allSatisfy { $0.deletedAt == nil })
        #expect(try count(Entry.self) == 3)
        #expect(try count(Photo.self) == 3)
        #expect(!context.hasChanges)
    }

    @Test func trashingAnEntryStampsOnlyThatEntry() throws {
        let topic = try topic("Sedona trip", entries: 3, photosEach: 1)
        let entry = try #require(topic.entries?.first)

        #expect(trash.moveToTrash(entry) == nil)

        #expect(entry.deletedAt == now)
        #expect(topic.deletedAt == nil)
        #expect(topic.liveEntries.count == 2)
        #expect(try count(Photo.self) == 3)
    }

    @Test func restoringATopicLeavesIndividuallyTrashedEntriesInTrash() throws {
        let topic = try topic("Sedona trip", entries: 3)
        topic.isArchived = true
        let individually = try #require(topic.entries?.first)
        _ = trash.moveToTrash(individually)
        _ = trash.moveToTrash(topic)

        #expect(trash.restore(topic) == nil)

        #expect(topic.deletedAt == nil)
        #expect(topic.isArchived)  // archived state is preserved
        #expect(individually.isTrashed)
        #expect(topic.liveEntries.count == 2)
        #expect(topic.liveEntries.allSatisfy { $0.isLive })
    }

    @Test func restoringAnEntryWithALiveTopic() throws {
        let topic = try topic("Sedona trip", entries: 2)
        let entry = try #require(topic.entries?.first)
        _ = trash.moveToTrash(entry)

        #expect(trash.restore(entry) == nil)

        #expect(entry.deletedAt == nil)
        #expect(entry.isLive)
        #expect(topic.liveEntries.count == 2)
    }

    @Test func restoringAnEntryInATrashedTopicRestoresBoth() throws {
        let topic = try topic("Sedona trip", entries: 3)
        let entries = topic.entries ?? []
        _ = trash.moveToTrash(entries[0])
        _ = trash.moveToTrash(entries[1])
        _ = trash.moveToTrash(topic)

        #expect(trash.restore(entries[0]) == nil)

        #expect(entries[0].deletedAt == nil)
        #expect(topic.deletedAt == nil)
        // The other individually trashed entry stays in Trash.
        #expect(entries[1].isTrashed)
        #expect(topic.liveEntries.count == 2)
    }

    // MARK: Permanent delete

    @Test func deletingATopicRemovesItsEntriesLiveAndTrashedAndTheirPhotos() throws {
        let doomed = try topic("Sedona trip", entries: 3, photosEach: 2)
        _ = trash.moveToTrash(try #require(doomed.entries?.first))
        let kept = try topic("Cigars", entries: 2, photosEach: 1)

        #expect(trash.deletePermanently(doomed) == nil)

        #expect(try fetch(Topic.self).map(\.title) == ["Cigars"])
        #expect(try count(Entry.self) == 2)
        #expect(try count(Photo.self) == 2)
        #expect(kept.liveEntries.count == 2)
        #expect(!context.hasChanges)
    }

    @Test func deletingAnEntryRemovesItAndItsPhotosOnly() throws {
        let topic = try topic("Sedona trip", entries: 3, photosEach: 2)
        let entry = try #require(topic.entries?.first)

        #expect(trash.deletePermanently(entry) == nil)

        #expect(try count(Topic.self) == 1)
        #expect(try count(Entry.self) == 2)
        #expect(try count(Photo.self) == 4)
        #expect(topic.liveEntries.count == 2)
    }

    @Test func emptyTrashRemovesEverythingTrashedAndNothingLive() throws {
        let live = try topic("Cigars", entries: 3, photosEach: 1)
        let trashedEntry = try #require(live.entries?.first)
        _ = trash.moveToTrash(trashedEntry)
        let trashedTopic = try topic("Kitchen remodel", entries: 2, photosEach: 1)
        // An entry trashed individually inside a topic that is also trashed.
        _ = trash.moveToTrash(try #require(trashedTopic.entries?.first))
        _ = trash.moveToTrash(trashedTopic)
        #expect(trash.emptyTrashCount() == 3)

        #expect(trash.emptyTrash() == nil)

        #expect(try fetch(Topic.self).map(\.title) == ["Cigars"])
        #expect(try count(Entry.self) == 2)
        #expect(try count(Photo.self) == 2)
        #expect(live.liveEntries.count == 2)
        #expect(trash.emptyTrashCount() == 0)
        #expect(try fetch(Entry.self).allSatisfy { !$0.isTrashed })
    }

    @Test func emptyTrashWithNothingInItChangesNothing() throws {
        _ = try topic("Cigars", entries: 2, photosEach: 1)

        #expect(trash.emptyTrash() == nil)

        #expect(try count(Topic.self) == 1)
        #expect(try count(Entry.self) == 2)
        #expect(try count(Photo.self) == 2)
    }

    // MARK: Purge

    @Test func thirtyDayPurgeRemovesOnlyItemsPastTheCutoff() throws {
        let fixture = try purgeFixture()

        // Two topics and two individually trashed entries are past 30 days.
        #expect(trash.purgeCount(retention: .thirtyDays) == 4)
        #expect(trash.purge(retention: .thirtyDays) == nil)

        // 40 and 100 days old go; 10 days old and live items stay.
        #expect(Set(try fetch(Topic.self).map(\.title)) == ["Live", "Trashed 10 days"])
        #expect(
            Set(try fetch(Entry.self).map(\.body)) == fixture.liveBodies.union(["entry 10 days"]))
        #expect(try count(Photo.self) == fixture.livePhotos + 1)
    }

    @Test func ninetyDayPurgeKeepsTheFortyDayOldItems() throws {
        let fixture = try purgeFixture()

        // One topic and one individually trashed entry are past 90 days.
        #expect(trash.purgeCount(retention: .ninetyDays) == 2)
        #expect(trash.purge(retention: .ninetyDays) == nil)

        #expect(
            Set(try fetch(Topic.self).map(\.title))
                == ["Live", "Trashed 10 days", "Trashed 40 days"]
        )
        #expect(
            Set(try fetch(Entry.self).map(\.body))
                == fixture.liveBodies.union(["entry 10 days", "entry 40 days", "in 40-day topic"])
        )
    }

    @Test func neverPurgesNothing() throws {
        _ = try purgeFixture()
        let before = (try count(Topic.self), try count(Entry.self), try count(Photo.self))

        #expect(trash.purgeCount(retention: .never) == 0)
        #expect(trash.purge(retention: .never) == nil)

        #expect(try count(Topic.self) == before.0)
        #expect(try count(Entry.self) == before.1)
        #expect(try count(Photo.self) == before.2)
    }

    @Test func purgeCutoffIsExact() throws {
        let cutoff = try #require(TrashRetention.thirtyDays.cutoff(before: now))
        let topic = try topic("Live", entries: 3)
        let entries = topic.entries ?? []
        entries[0].body = "at cutoff"
        entries[0].deletedAt = cutoff
        entries[1].body = "one second inside"
        entries[1].deletedAt = cutoff.addingTimeInterval(1)
        entries[2].body = "one second past"
        entries[2].deletedAt = cutoff.addingTimeInterval(-1)
        try context.save()

        #expect(trash.purgeCount(retention: .thirtyDays) == 2)
        #expect(trash.purge(retention: .thirtyDays) == nil)

        #expect(try fetch(Entry.self).map(\.body) == ["one second inside"])
    }

    @Test func purgeNeverTouchesLiveItemsHoweverOld() throws {
        let topic = try topic("Old but live", entries: 2, photosEach: 1)
        topic.createdAt = now.addingTimeInterval(-400 * 86_400)
        try context.save()

        #expect(trash.purge(retention: .thirtyDays) == nil)

        #expect(try count(Topic.self) == 1)
        #expect(try count(Entry.self) == 2)
        #expect(try count(Photo.self) == 2)
    }

    // MARK: Counts and live helpers

    @Test func topicDeleteCountIncludesTrashedEntries() throws {
        let topic = try topic("Sedona trip", entries: 4)
        _ = trash.moveToTrash(try #require(topic.entries?.first))

        #expect(topic.liveEntries.count == 3)
        #expect(TrashOperations.entriesDeleted(with: topic) == 4)
    }

    @Test func entriesOfATrashedTopicAreNotLive() throws {
        let topic = try topic("Sedona trip", entries: 2)
        let entries = topic.entries ?? []
        #expect(entries.allSatisfy { $0.isLive })

        _ = trash.moveToTrash(topic)

        // Not trashed themselves, and still what the topic brings back, but not live.
        #expect(entries.allSatisfy { !$0.isTrashed })
        #expect(entries.allSatisfy { !$0.isLive })
        #expect(topic.liveEntries.count == 2)
    }

    @Test func lastUsedTopicAndListSectionsSkipTrashedTopics() throws {
        let cigars = try topic("Cigars", entries: 1)
        let sedona = try topic("Sedona trip", entries: 1)
        let stored = try #require(LastUsedTopic.encode(sedona))
        _ = trash.moveToTrash(sedona)

        #expect(LastUsedTopic.resolve(stored: stored, among: [cigars, sedona]) === cigars)
        let listed = try context.fetch(
            FetchDescriptor<Topic>(predicate: #Predicate { $0.deletedAt == nil })
        )
        #expect(TopicListSections(topics: listed, sort: .name).live.map(\.title) == ["Cigars"])
    }

    @Test func placeNameBackfillSkipsEntriesOfTrashedTopics() throws {
        let topic = try topic("Sedona trip", entries: 1)
        let entry = try #require(topic.entries?.first)
        entry.latitude = 34.86
        entry.longitude = -111.76
        try context.save()
        #expect(LocationCapture.needsPlaceName(entry))

        _ = trash.moveToTrash(topic)

        #expect(!LocationCapture.needsPlaceName(entry))
    }

    @Test func readingOrderAfterTrashingFallsBackToANeighbor() throws {
        let topic = try topic("Sedona trip", entries: 3)
        let ordered = EntryTimeline.readingOrder(topic.liveEntries)
        let replacement = EntryTimeline.replacement(for: ordered[1], in: topic.liveEntries)

        _ = trash.moveToTrash(ordered[1])

        #expect(replacement === ordered[2])
        #expect(
            EntryTimeline.readingOrder(topic.liveEntries).map(\.body) == [
                ordered[0].body, ordered[2].body,
            ])
        #expect(EntryTimeline.neighbors(of: ordered[1], in: topic.liveEntries) == nil)
    }

    // MARK: Helpers

    /// A saved topic with `entries` entries dated a day apart, each with `photosEach` photos.
    private func topic(_ title: String, entries: Int, photosEach: Int = 0) throws -> Topic {
        let topic = Topic(title: title)
        context.insert(topic)
        for index in 0..<entries {
            let entry = Entry(
                body: "\(title) \(index)",
                date: now.addingTimeInterval(Double(index - entries) * 86_400),
                topic: topic
            )
            context.insert(entry)
            for order in 0..<photosEach {
                context.insert(Photo(order: order, entry: entry))
            }
        }
        try context.save()
        return topic
    }

    /// A live topic, plus topics and entries trashed 10, 40, and 100 days ago.
    private func purgeFixture() throws -> (liveBodies: Set<String>, livePhotos: Int) {
        let live = try topic("Live", entries: 5, photosEach: 1)
        let liveEntries = live.entries ?? []
        for (entry, days) in zip(liveEntries.prefix(3), [10.0, 40.0, 100.0]) {
            entry.body = "entry \(Int(days)) days"
            entry.deletedAt = now.addingTimeInterval(-days * 86_400)
        }
        for days in [10.0, 40.0, 100.0] {
            let trashed = try topic("Trashed \(Int(days)) days", entries: 1)
            trashed.entries?.first?.body = "in \(Int(days))-day topic"
            trashed.deletedAt = now.addingTimeInterval(-days * 86_400)
        }
        try context.save()
        let liveBodies = Set(liveEntries.suffix(2).map(\.body)).union(["in 10-day topic"])
        return (liveBodies, 2)
    }

    private func fetch<Model: PersistentModel>(_ type: Model.Type) throws -> [Model] {
        try context.fetch(FetchDescriptor<Model>())
    }

    private func count<Model: PersistentModel>(_ type: Model.Type) throws -> Int {
        try context.fetchCount(FetchDescriptor<Model>())
    }
}
