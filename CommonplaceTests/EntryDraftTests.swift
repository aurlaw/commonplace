import Foundation
import Observation
import SwiftData
import Testing

@testable import Commonplace

@MainActor
struct EntryDraftTests {
    private let container: ModelContainer
    private let context: ModelContext
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    init() throws {
        container = try ModelContainerFactory.makeInMemory()
        context = ModelContext(container)
    }

    // MARK: Trimming and validation

    @Test func trimmedBodyRemovesSurroundingWhitespaceAndKeepsInnerLineBreaks() {
        var draft = newDraft(in: topic("Sedona trip"))
        draft.body = "\n  First paragraph.\n\nSecond paragraph.  \n\n"

        #expect(draft.trimmedBody == "First paragraph.\n\nSecond paragraph.")
    }

    @Test func isValidNeedsATopicAndText() {
        let sedona = topic("Sedona trip")

        var draft = EntryDraft(mode: .newFromList, now: now)
        draft.body = "Arrived."
        #expect(!draft.isValid)  // no topic

        draft.topic = sedona
        #expect(draft.isValid)

        draft.body = ""
        #expect(!draft.isValid)

        draft.body = "  \n\t "
        #expect(!draft.isValid)

        draft.body = "  Arrived.  "
        #expect(draft.isValid)
    }

    // MARK: Writing to models

    @Test func makeEntryUsesTheTopicDateAndTrimmedBody() throws {
        let sedona = topic("Sedona trip")
        var draft = newDraft(in: sedona)
        draft.body = "  Arrived. 91° at check-in.\n"
        draft.date = now.addingTimeInterval(-86_400)

        let entry = draft.makeEntry()
        context.insert(entry)
        try context.save()

        #expect(entry.body == "Arrived. 91° at check-in.")
        #expect(entry.date == now.addingTimeInterval(-86_400))
        #expect(entry.topic === sedona)
        #expect(sedona.liveEntries.map(\.body) == ["Arrived. 91° at check-in."])
        #expect(entry.deletedAt == nil)
        #expect(entry.hasLocation == false)
        #expect(entry.photos?.isEmpty == true)
    }

    @Test func makeEntryNeverIncludesPendingDictation() {
        var draft = newDraft(in: topic("Sedona trip"))
        draft.body = "Back at the car. "
        draft.dictation = .sample

        #expect(draft.makeEntry().body == "Back at the car.")
    }

    @Test func applyUpdatesBodyAndDateOnly() throws {
        let sedona = topic("Sedona trip")
        let createdAt = now.addingTimeInterval(-10_000)
        let deletedAt = now.addingTimeInterval(-50)
        let entry = Entry(
            body: "Old text", date: now.addingTimeInterval(-5_000), topic: sedona,
            createdAt: createdAt)
        entry.latitude = 34.8697
        entry.longitude = -111.7610
        entry.placeName = "Sedona, AZ"
        entry.deletedAt = deletedAt
        context.insert(entry)
        let photo = Photo(order: 0, entry: entry)
        context.insert(photo)
        try context.save()

        var draft = EntryDraft(mode: .edit(entry), now: now)
        draft.body = "  New text.\n\nSecond paragraph. "
        draft.date = now.addingTimeInterval(-2_000)
        draft.photos = []
        draft.topic = topic("Cigars")
        draft.dictation = .sample
        draft.apply(to: entry)
        try context.save()

        #expect(entry.body == "New text.\n\nSecond paragraph.")
        #expect(entry.date == now.addingTimeInterval(-2_000))
        #expect(entry.topic === sedona)
        #expect(entry.photos?.map(\.persistentModelID) == [photo.persistentModelID])
        #expect(entry.latitude == 34.8697)
        #expect(entry.longitude == -111.7610)
        #expect(entry.placeName == "Sedona, AZ")
        #expect(entry.createdAt == createdAt)
        #expect(entry.deletedAt == deletedAt)
        #expect(try context.fetchCount(FetchDescriptor<Entry>()) == 1)
    }

    @Test func draftFromEditModeCopiesTheEntry() {
        let sedona = topic("Sedona trip")
        let entry = Entry(body: "Arrived.", date: now.addingTimeInterval(-100), topic: sedona)
        context.insert(entry)

        let draft = EntryDraft(mode: .edit(entry), now: now)

        #expect(draft.body == "Arrived.")
        #expect(draft.date == now.addingTimeInterval(-100))
        #expect(draft.topic === sedona)
    }

    @Test func newDraftsStartAtNow() {
        let sedona = topic("Sedona trip")

        #expect(EntryDraft(mode: .newFromList, now: now).date == now)
        #expect(EntryDraft(mode: .newFromList, now: now).topic == nil)
        #expect(EntryDraft(mode: .newInTopic(sedona), now: now).date == now)
        #expect(EntryDraft(mode: .newInTopic(sedona), now: now).topic === sedona)
    }

    // MARK: Dirty detection

    @Test func pristineDraftIsNotDirty() {
        let original = newDraft(in: topic("Sedona trip"))

        #expect(!original.isDirty(comparedTo: original))
    }

    @Test func changingBodyDateOrTopicIsDirty() {
        let original = newDraft(in: topic("Sedona trip"))

        var draft = original
        draft.body = "Arrived."
        #expect(draft.isDirty(comparedTo: original))

        draft = original
        draft.date = now.addingTimeInterval(-60)
        #expect(draft.isDirty(comparedTo: original))

        draft = original
        draft.topic = topic("Cigars")
        #expect(draft.isDirty(comparedTo: original))
    }

    @Test func whitespaceOnlyBodyChangesAreNotDirty() {
        var original = newDraft(in: topic("Sedona trip"))
        var draft = original
        draft.body = "  \n "
        #expect(!draft.isDirty(comparedTo: original))

        original.body = "Arrived."
        draft = original
        draft.body = "Arrived.\n\n"
        #expect(!draft.isDirty(comparedTo: original))
    }

    @Test func dictationAndPhotosNeverMakeADraftDirty() {
        let original = newDraft(in: topic("Sedona trip"))
        var draft = original
        draft.dictation = .sample
        draft.photos = [Photo()]

        #expect(!draft.isDirty(comparedTo: original))
    }

    // MARK: What the screens read after a save

    @Test func timelineGroupsInsertedEntriesByMonthNewestFirst() throws {
        let sedona = topic("Sedona trip")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        func date(_ month: Int, _ day: Int, _ hour: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))
                ?? .distantPast
        }

        for (body, when) in [
            ("oct-2", date(10, 2, 6)), ("sep-30", date(9, 30, 16)), ("oct-4", date(10, 4, 5)),
        ] {
            var draft = newDraft(in: sedona)
            draft.body = body
            draft.date = when
            context.insert(draft.makeEntry())
        }
        try context.save()

        // Back-dating an existing entry moves it to the earlier month.
        let moved = try #require(sedona.liveEntries.first { $0.body == "oct-2" })
        var edit = EntryDraft(mode: .edit(moved), now: now)
        edit.date = date(9, 12, 9)
        edit.apply(to: moved)
        // A trashed entry stays out of the timeline.
        let trashed = Entry(body: "trashed", date: date(10, 3, 9), topic: sedona)
        trashed.deletedAt = now
        context.insert(trashed)
        try context.save()

        let sections = EntryTimeline.groupByMonth(sedona.liveEntries, calendar: calendar)

        #expect(
            sections.map { $0.title(calendar: calendar) } == ["October 2026", "September 2026"])
        #expect(sections.map { $0.entries.map(\.body) } == [["oct-4"], ["sep-30", "oct-2"]])
        #expect(sedona.lastEntryDate == date(10, 4, 5))
    }

    /// The topic screens read entries through `Topic.entries`. SwiftUI refreshes them only if
    /// that relationship reports a change when an entry is saved into the topic.
    @Test func savingANewEntryIsObservedThroughTheTopicsEntries() async throws {
        let sedona = topic("Sedona trip")
        try context.save()
        var draft = newDraft(in: sedona)
        draft.body = "Arrived."

        try await confirmation("Topic.entries reported a change") { changed in
            withObservationTracking {
                _ = sedona.liveEntries
            } onChange: {
                changed()
            }
            context.insert(draft.makeEntry())
            try context.save()
        }
        #expect(sedona.liveEntries.count == 1)
    }

    @Test func editingAnEntryIsObservedThroughItsProperties() async throws {
        let entry = Entry(body: "Old", date: now, topic: topic("Sedona trip"))
        context.insert(entry)
        try context.save()
        var draft = EntryDraft(mode: .edit(entry), now: now)
        draft.body = "New"

        try await confirmation("Entry.body reported a change") { changed in
            withObservationTracking {
                _ = entry.body
            } onChange: {
                changed()
            }
            draft.apply(to: entry)
            try context.save()
        }
    }

    // MARK: Helpers

    private func topic(_ title: String) -> Topic {
        let topic = Topic(title: title)
        context.insert(topic)
        return topic
    }

    private func newDraft(in topic: Topic) -> EntryDraft {
        EntryDraft(mode: .newInTopic(topic), now: now)
    }
}
