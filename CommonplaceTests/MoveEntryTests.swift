import Foundation
import SwiftData
import Testing

@testable import Commonplace

@MainActor
struct MoveEntryTests {
    private let container: ModelContainer
    private let context: ModelContext
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let sedona: Topic
    private let dollySods: Topic

    init() throws {
        container = try ModelContainerFactory.makeInMemory()
        context = ModelContext(container)
        sedona = Topic(title: "Sedona trip")
        sedona.capturesLocation = true
        dollySods = Topic(title: "Dolly Sods")
        context.insert(sedona)
        context.insert(dollySods)
        try context.save()
    }

    // MARK: Destinations

    @Test func destinationsExcludeTheCurrentAndTrashedTopicsAndListArchivedLast() throws {
        let recent = try topic("Recent", lastEntryDaysAgo: 1)
        let older = try topic("Older", lastEntryDaysAgo: 30)
        let archivedRecent = try topic("Archived recent", lastEntryDaysAgo: 2, archived: true)
        let archivedOld = try topic("Archived old", lastEntryDaysAgo: 90, archived: true)
        let trashed = try topic("Trashed", lastEntryDaysAgo: 0)
        trashed.deletedAt = now
        let current = try topic("Current", lastEntryDaysAgo: 0)

        let destinations = TopicDestinations(
            topics: [older, trashed, archivedOld, current, recent, archivedRecent],
            excluding: current
        )

        #expect(destinations.active.map(\.title) == ["Recent", "Older"])
        #expect(destinations.archived.map(\.title) == ["Archived recent", "Archived old"])
        #expect(!destinations.isEmpty)
    }

    @Test func destinationsWithoutAnExclusionIncludeEveryLiveTopic() {
        dollySods.isArchived = true

        let choices = TopicDestinations(topics: [sedona, dollySods])

        #expect(choices.active.map(\.title) == ["Sedona trip"])
        #expect(choices.archived.map(\.title) == ["Dolly Sods"])
    }

    @Test func noOtherTopicMeansNoDestinations() {
        #expect(TopicDestinations(topics: [sedona], excluding: sedona).isEmpty)
    }

    // MARK: Composer (edit mode)

    @Test func changingTheTopicWhileEditingIsDirty() throws {
        let entry = try entry(in: sedona)
        let original = EntryDraft(mode: .edit(entry), now: now)
        var draft = original

        draft.setTopic(dollySods)
        #expect(draft.isDirty(comparedTo: original))

        draft.setTopic(sedona)
        #expect(!draft.isDirty(comparedTo: original))
    }

    @Test func applyWritesTheNewTopicAndNothingElseTravelsOrChanges() throws {
        let entry = try entry(in: sedona, photos: 2, located: true)
        let createdAt = entry.createdAt
        let photoIDs = entry.sortedPhotos.map(\.persistentModelID)
        var draft = EntryDraft(mode: .edit(entry), now: now)

        draft.setTopic(dollySods)
        draft.apply(to: entry)
        try context.save()

        #expect(entry.topic === dollySods)
        #expect(entry.sortedPhotos.map(\.persistentModelID) == photoIDs)
        #expect(entry.latitude == 34.8253)
        #expect(entry.longitude == -111.7885)
        #expect(entry.placeName == "Cathedral Rock Trailhead")
        #expect(entry.createdAt == createdAt)
        #expect(entry.deletedAt == nil)
        #expect(dollySods.liveEntries.map(\.persistentModelID) == [entry.persistentModelID])
        #expect(sedona.liveEntries.isEmpty)
    }

    @Test func applyWithTheSameTopicLeavesItAlone() throws {
        let entry = try entry(in: sedona)
        var draft = EntryDraft(mode: .edit(entry), now: now)
        draft.body = "Edited"

        draft.apply(to: entry)

        #expect(entry.topic === sedona)
        #expect(entry.body == "Edited")
    }

    @Test func setTopicWhileEditingLeavesTheLocationAlone() throws {
        let withLocation = try entry(in: dollySods, located: true)
        var draft = EntryDraft(mode: .edit(withLocation), now: now)
        let location = draft.location

        // Dolly Sods doesn't capture location; moving there must not remove it.
        draft.setTopic(dollySods)
        draft.setTopic(sedona)
        #expect(draft.capturesLocation)
        #expect(draft.location == location)
        #expect(!draft.needsCapture)

        let without = try entry(in: dollySods)
        var plain = EntryDraft(mode: .edit(without), now: now)
        // Sedona captures location for new entries; moving there must not add one.
        plain.setTopic(sedona)
        #expect(!plain.capturesLocation)
        #expect(!plain.needsCapture)

        plain.applyLocation(to: without)
        #expect(!without.hasLocation)
    }

    @Test func setTopicForANewEntryStillFollowsTheTopic() {
        var draft = EntryDraft(mode: .newFromList, now: now)

        draft.setTopic(sedona)
        #expect(draft.capturesLocation)
        #expect(draft.needsCapture)

        draft.setTopic(dollySods)
        #expect(!draft.capturesLocation)
    }

    // MARK: Move operation

    @Test func moveReassignsTheTopicAndKeepsPhotosAndLocation() throws {
        let entry = try entry(in: sedona, photos: 3, located: true)
        let photoIDs = entry.sortedPhotos.map(\.persistentModelID)
        let date = entry.date

        #expect(EntryOperations(context: context).move(entry, to: dollySods) == nil)

        #expect(entry.topic === dollySods)
        #expect(entry.sortedPhotos.map(\.persistentModelID) == photoIDs)
        #expect(entry.sortedPhotos.allSatisfy { $0.entry === entry })
        #expect(entry.latitude == 34.8253)
        #expect(entry.placeName == "Cathedral Rock Trailhead")
        #expect(entry.date == date)
        #expect(dollySods.liveEntries.contains { $0 === entry })
        #expect(!sedona.liveEntries.contains { $0 === entry })
        #expect(dollySods.lastEntryDate == date)
        #expect(sedona.lastEntryDate == nil)
        #expect(!context.hasChanges)
        #expect(try context.fetchCount(FetchDescriptor<Photo>()) == 3)
    }

    @Test func moveIntoAnArchivedTopic() throws {
        dollySods.isArchived = true
        let entry = try entry(in: sedona)

        #expect(EntryOperations(context: context).move(entry, to: dollySods) == nil)

        #expect(entry.topic === dollySods)
        #expect(entry.isLive)
        #expect(dollySods.isArchived)
    }

    @Test func moveIgnoresTrashedEntriesTrashedTopicsAndTheSameTopic() throws {
        let trashedEntry = try entry(in: sedona)
        trashedEntry.deletedAt = now
        let liveEntry = try entry(in: sedona)
        let trashedTopic = Topic(title: "Kitchen remodel")
        trashedTopic.deletedAt = now
        context.insert(trashedTopic)
        try context.save()
        let operations = EntryOperations(context: context)

        #expect(operations.move(trashedEntry, to: dollySods) == nil)
        #expect(trashedEntry.topic === sedona)

        #expect(operations.move(liveEntry, to: trashedTopic) == nil)
        #expect(liveEntry.topic === sedona)

        #expect(operations.move(liveEntry, to: sedona) == nil)
        #expect(liveEntry.topic === sedona)
        #expect(!context.hasChanges)
    }

    @Test func rolledBackMoveLeavesTheEntryInItsTopic() throws {
        let entry = try entry(in: sedona)

        entry.topic = dollySods
        context.rollback()

        #expect(entry.topic === sedona)
        #expect(sedona.liveEntries.contains { $0 === entry })
    }

    @Test func lastUsedTopicIsUnchangedByAMove() throws {
        let entry = try entry(in: sedona)
        let stored = try #require(LastUsedTopic.encode(sedona))
        let before = LastUsedTopic.resolve(stored: stored, among: [sedona, dollySods])

        _ = EntryOperations(context: context).move(entry, to: dollySods)

        #expect(before === sedona)
        #expect(LastUsedTopic.resolve(stored: stored, among: [sedona, dollySods]) === sedona)
    }

    @Test func detailFallsBackToANeighborAfterAMove() throws {
        let first = try entry(in: sedona, daysAgo: 3)
        let middle = try entry(in: sedona, daysAgo: 2)
        let last = try entry(in: sedona, daysAgo: 1)
        let replacement = EntryTimeline.replacement(for: middle, in: sedona.liveEntries)

        _ = EntryOperations(context: context).move(middle, to: dollySods)

        #expect(replacement === last)
        #expect(
            EntryTimeline.readingOrder(sedona.liveEntries).map(\.persistentModelID)
                == [first, last].map(\.persistentModelID))
    }

    // MARK: Helpers

    private func topic(
        _ title: String, lastEntryDaysAgo days: Double, archived: Bool = false
    ) throws -> Topic {
        let topic = Topic(title: title)
        topic.isArchived = archived
        context.insert(topic)
        context.insert(
            Entry(body: title, date: now.addingTimeInterval(-days * 86_400), topic: topic))
        try context.save()
        return topic
    }

    private func entry(
        in topic: Topic, photos: Int = 0, located: Bool = false, daysAgo: Double = 1
    ) throws -> Entry {
        let entry = Entry(
            body: "Entry", date: now.addingTimeInterval(-daysAgo * 86_400), topic: topic)
        if located {
            entry.latitude = 34.8253
            entry.longitude = -111.7885
            entry.placeName = "Cathedral Rock Trailhead"
        }
        context.insert(entry)
        for order in 0..<photos {
            context.insert(Photo(order: order, entry: entry))
        }
        try context.save()
        return entry
    }
}
