import Foundation
import SwiftData
import Testing

@testable import Commonplace

@MainActor
struct EntryTimelineTests {
    private let container: ModelContainer
    private let context: ModelContext
    private let calendar: Calendar

    init() throws {
        container = try ModelContainerFactory.makeInMemory()
        context = ModelContext(container)
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        self.calendar = calendar
    }

    // MARK: lastEntryLabel

    @Test func lastEntryLabelToday() {
        let now = date(2026, 10, 5, 8, 0)
        #expect(label(for: date(2026, 10, 5, 0, 1), now: now) == "Today")
        #expect(label(for: date(2026, 10, 5, 23, 59), now: now) == "Today")
    }

    @Test func lastEntryLabelYesterday() {
        let now = date(2026, 10, 5, 8, 0)
        #expect(label(for: date(2026, 10, 4, 23, 59), now: now) == "Yesterday")
        #expect(label(for: date(2026, 10, 4, 0, 0), now: now) == "Yesterday")
    }

    @Test func lastEntryLabelEarlierThisYear() {
        let now = date(2026, 10, 5, 8, 0)
        #expect(label(for: date(2026, 10, 3, 23, 59), now: now) == "Oct 3")
        #expect(label(for: date(2026, 9, 28, 20, 15), now: now) == "Sep 28")
    }

    @Test func lastEntryLabelPreviousYear() {
        let now = date(2026, 10, 5, 8, 0)
        #expect(label(for: date(2025, 9, 28, 20, 15), now: now) == "Sep 28, 2025")
    }

    @Test func lastEntryLabelYesterdayAcrossYearBoundary() {
        let now = date(2026, 1, 1, 8, 0)
        #expect(label(for: date(2025, 12, 31, 22, 0), now: now) == "Yesterday")
    }

    // MARK: groupByMonth

    @Test func groupByMonthOrdersMonthsAndEntriesNewestFirstAcrossYearBoundary() {
        let entries = [
            entry("dec-early", at: date(2025, 12, 3, 9, 0)),
            entry("jan-late", at: date(2026, 1, 20, 9, 0)),
            entry("oct", at: date(2025, 10, 31, 23, 59)),
            entry("dec-late", at: date(2025, 12, 28, 9, 0)),
            entry("jan-early", at: date(2026, 1, 1, 0, 0)),
            entry("dec-mid", at: date(2025, 12, 28, 8, 0)),
        ]

        let sections = EntryTimeline.groupByMonth(entries, calendar: calendar)

        #expect(
            sections.map { $0.title(calendar: calendar) }
                == ["January 2026", "December 2025", "October 2025"]
        )
        #expect(
            sections.map { $0.entries.map(\.body) }
                == [["jan-late", "jan-early"], ["dec-late", "dec-mid", "dec-early"], ["oct"]]
        )
    }

    @Test func groupByMonthOfNothingIsEmpty() {
        #expect(EntryTimeline.groupByMonth([], calendar: calendar).isEmpty)
    }

    // MARK: neighbors

    @Test func neighborsOfFirstMiddleAndLast() throws {
        let first = entry("first", at: date(2026, 10, 1, 15, 15))
        let middle = entry("middle", at: date(2026, 10, 2, 6, 10))
        let last = entry("last", at: date(2026, 10, 3, 8, 50))
        let entries = [last, first, middle]

        let firstNeighbors = try #require(EntryTimeline.neighbors(of: first, in: entries))
        #expect(firstNeighbors.previous == nil)
        #expect(firstNeighbors.next === middle)
        #expect(firstNeighbors.positionLabel == "1 of 3")

        let middleNeighbors = try #require(EntryTimeline.neighbors(of: middle, in: entries))
        #expect(middleNeighbors.previous === first)
        #expect(middleNeighbors.next === last)
        #expect(middleNeighbors.positionLabel == "2 of 3")

        let lastNeighbors = try #require(EntryTimeline.neighbors(of: last, in: entries))
        #expect(lastNeighbors.previous === middle)
        #expect(lastNeighbors.next == nil)
        #expect(lastNeighbors.positionLabel == "3 of 3")
    }

    @Test func neighborsOfSingleEntry() throws {
        let only = entry("only", at: date(2026, 10, 2, 6, 10))

        let neighbors = try #require(EntryTimeline.neighbors(of: only, in: [only]))

        #expect(neighbors.previous == nil)
        #expect(neighbors.next == nil)
        #expect(neighbors.positionLabel == "1 of 1")
    }

    @Test func neighborsOfEntryOutsideTheListIsNil() {
        let inside = entry("inside", at: date(2026, 10, 2, 6, 10))
        let outside = entry("outside", at: date(2026, 10, 3, 6, 10))

        #expect(EntryTimeline.neighbors(of: outside, in: [inside]) == nil)
    }

    // MARK: readingOrder

    @Test func readingOrderIsOldestToNewest() {
        let entries = [
            entry("oct-3", at: date(2026, 10, 3, 8, 50)),
            entry("sep-30", at: date(2026, 9, 30, 16, 40)),
            entry("oct-2", at: date(2026, 10, 2, 6, 10)),
            entry("dec-2025", at: date(2025, 12, 31, 23, 59)),
        ]

        #expect(
            EntryTimeline.readingOrder(entries).map(\.body)
                == ["dec-2025", "sep-30", "oct-2", "oct-3"]
        )
    }

    @Test func readingOrderBreaksTiesByCreatedAt() {
        let moment = date(2026, 10, 2, 6, 10)
        let second = entry("second", at: moment, createdAt: date(2026, 10, 2, 9, 0))
        let third = entry("third", at: moment, createdAt: date(2026, 10, 2, 10, 0))
        let first = entry("first", at: moment, createdAt: date(2026, 10, 2, 8, 0))

        #expect(
            EntryTimeline.readingOrder([second, third, first]).map(\.body)
                == ["first", "second", "third"]
        )
    }

    @Test func readingOrderOfEmptyAndSingleInputs() {
        let only = entry("only", at: date(2026, 10, 2, 6, 10))

        #expect(EntryTimeline.readingOrder([]).isEmpty)
        #expect(EntryTimeline.readingOrder([only]).map(\.body) == ["only"])
    }

    @Test func neighborsAgreeWithReadingOrder() throws {
        let moment = date(2026, 10, 2, 6, 10)
        let entries = [
            entry("c", at: date(2026, 10, 3, 8, 50)),
            entry("b-later", at: moment, createdAt: date(2026, 10, 2, 9, 0)),
            entry("a", at: date(2026, 9, 30, 16, 40)),
            entry("b-earlier", at: moment, createdAt: date(2026, 10, 2, 8, 0)),
        ]
        let ordered = EntryTimeline.readingOrder(entries)

        for (index, entry) in ordered.enumerated() {
            let neighbors = try #require(EntryTimeline.neighbors(of: entry, in: entries))
            #expect(neighbors.position == index + 1)
            #expect(neighbors.count == ordered.count)
            #expect(neighbors.previous === (index > 0 ? ordered[index - 1] : nil))
            #expect(neighbors.next === (index < ordered.count - 1 ? ordered[index + 1] : nil))
        }
    }

    @Test func readingOrderIsTheReverseOfTheTimeline() {
        let entries = [
            entry("oct-3", at: date(2026, 10, 3, 8, 50)),
            entry("sep-30", at: date(2026, 9, 30, 16, 40)),
            entry("oct-2", at: date(2026, 10, 2, 6, 10)),
        ]
        let timeline = EntryTimeline.groupByMonth(entries, calendar: calendar).flatMap(\.entries)

        #expect(EntryTimeline.readingOrder(entries).map(\.body) == timeline.reversed().map(\.body))
    }

    // MARK: replacement

    @Test func replacementForAMiddleEntryIsItsNewerNeighbor() {
        let older = entry("older", at: date(2026, 10, 1, 15, 15))
        let middle = entry("middle", at: date(2026, 10, 2, 6, 10))
        let newer = entry("newer", at: date(2026, 10, 3, 8, 50))
        let newest = entry("newest", at: date(2026, 10, 4, 5, 58))
        let entries = [newest, older, middle, newer]

        #expect(EntryTimeline.replacement(for: middle, in: entries) === newer)
        #expect(EntryTimeline.replacement(for: older, in: entries) === middle)
    }

    @Test func replacementForTheNewestEntryIsItsOlderNeighbor() {
        let older = entry("older", at: date(2026, 10, 1, 15, 15))
        let middle = entry("middle", at: date(2026, 10, 2, 6, 10))
        let newest = entry("newest", at: date(2026, 10, 3, 8, 50))

        #expect(EntryTimeline.replacement(for: newest, in: [older, newest, middle]) === middle)
    }

    @Test func replacementForTheOnlyEntryIsNil() {
        let only = entry("only", at: date(2026, 10, 2, 6, 10))

        #expect(EntryTimeline.replacement(for: only, in: [only]) == nil)
        #expect(EntryTimeline.replacement(for: only, in: []) == nil)
    }

    /// Once an entry is trashed it is no longer among the topic's live entries.
    @Test func replacementWorksWhenTheEntryHasAlreadyLeftTheList() {
        let older = entry("older", at: date(2026, 10, 1, 15, 15))
        let trashed = entry("trashed", at: date(2026, 10, 2, 6, 10))
        let newer = entry("newer", at: date(2026, 10, 3, 8, 50))

        #expect(EntryTimeline.replacement(for: trashed, in: [older, newer]) === newer)
        #expect(EntryTimeline.replacement(for: trashed, in: [older]) === older)
        #expect(EntryTimeline.replacement(for: newer, in: [older]) === older)
    }

    // MARK: Other labels

    @Test func dateLabels() {
        let moment = date(2026, 10, 2, 6, 10)
        let now = date(2026, 10, 5, 8, 0)

        #expect(EntryTimeline.dayNumber(moment, calendar: calendar) == "2")
        #expect(EntryTimeline.weekday(moment, calendar: calendar) == "Fri")
        #expect(EntryTimeline.monthDay(moment, calendar: calendar) == "Oct 2")
        #expect(EntryTimeline.fullDate(moment, calendar: calendar) == "Friday, October 2, 2026")
        #expect(clockTime(EntryTimeline.time(moment, calendar: calendar)) == "6:10 AM")
        #expect(
            clockTime(EntryTimeline.composerDate(moment, now: now, calendar: calendar))
                == "Oct 2, 2026, 6:10 AM"
        )
        #expect(
            clockTime(
                EntryTimeline.composerDate(date(2026, 10, 5, 6, 42), now: now, calendar: calendar))
                == "Today, 6:42 AM"
        )
    }

    @Test func entryCountPluralizes() {
        #expect(EntryTimeline.entryCount(0) == "0 entries")
        #expect(EntryTimeline.entryCount(1) == "1 entry")
        #expect(EntryTimeline.entryCount(23) == "23 entries")
    }

    // MARK: Helpers

    private func label(for date: Date, now: Date) -> String {
        EntryTimeline.lastEntryLabel(for: date, now: now, calendar: calendar)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        let components = DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        )
        return calendar.date(from: components) ?? .distantPast
    }

    private func entry(_ body: String, at date: Date, createdAt: Date = .now) -> Entry {
        let entry = Entry(body: body, date: date, createdAt: createdAt)
        context.insert(entry)
        return entry
    }

    /// Time formats separate the period with a narrow no-break space; compare with a plain one.
    private func clockTime(_ string: String) -> String {
        string.replacing("\u{202F}", with: " ")
    }
}
