import Foundation
import SwiftData
import Testing

@testable import Commonplace

// MARK: Query

struct SearchQueryTests {
    @Test func tokenizesOnWhitespace() {
        #expect(SearchQuery("  sunrise \n mesa\t").tokens == ["sunrise", "mesa"])
    }

    @Test func dropsPunctuationOnlyTokensAndTrimsPunctuation() {
        #expect(SearchQuery("— mesa, ... (loop)").tokens == ["mesa", "loop"])
        // Inner punctuation is kept.
        #expect(SearchQuery("6:15 Devil’s").tokens == ["6:15", "Devil’s"])
    }

    @Test func emptyAndShortQueriesAreNotSearchable() {
        #expect(SearchQuery("").tokens.isEmpty)
        #expect(!SearchQuery("").isSearchable)
        #expect(!SearchQuery("   ").isSearchable)
        #expect(!SearchQuery(" a ").isSearchable)
        #expect(!SearchQuery("--").isSearchable)
        #expect(SearchQuery("az").isSearchable)
    }

    @Test func everyTokenMustMatchInAnyOrder() {
        let text = "Last sunrise. Airport Mesa overlook was packed."
        #expect(SearchQuery("mesa sunrise").matches(text))
        #expect(SearchQuery("sunrise").matches(text))
        #expect(!SearchQuery("sunrise sunset").matches(text))
    }

    @Test func ignoresCaseAndDiacritics() {
        #expect(SearchQuery("cafe").matches("Elote Café"))
        #expect(SearchQuery("CAFÉ").matches("elote cafe"))
        #expect(SearchQuery("padron").matches("Padrón 1964 Maduro"))
    }

    @Test func tokensCanMatchAcrossBodyAndPlaceName() {
        let query = SearchQuery("corn sedona")
        #expect(query.matches(["Get the fire-roasted corn.", "Sedona, AZ"]))
        #expect(!query.matches(["Get the fire-roasted corn.", ""]))
    }

    @Test func matchRangesFindEveryOccurrenceInOrder() {
        let text = "Mesa to mesa, then sunrise."
        let ranges = SearchQuery("sunrise mesa").matchRanges(in: text)
        #expect(ranges.map { String(text[$0]) } == ["Mesa", "mesa", "sunrise"])
    }

    @Test func overlappingMatchesAreMerged() {
        let text = "Cathedral"
        let ranges = SearchQuery("cathe hedral").matchRanges(in: text)
        #expect(ranges.map { String(text[$0]) } == ["Cathedral"])
    }
}

// MARK: Snippet

struct SearchSnippetTests {
    private let long = """
        Cathedral Rock at first light. Trailhead lot was already half full at 5:40, mostly \
        headlamps and tripods.

        The trail is short — barely over a mile round trip — but the last third is a \
        hands-and-feet scramble up the chute. Easier going up than coming down. We sat at the \
        saddle for twenty minutes while the sun hit Courthouse Butte first.
        """

    private func highlighted(_ snippet: SearchSnippet) -> [String] {
        snippet.highlights.map { String(snippet.text[$0]) }
    }

    @Test func matchAtTheStartIsNotTrimmedAtTheStart() {
        let snippet = SearchSnippet(body: long, placeName: nil, query: SearchQuery("cathedral"))

        #expect(snippet.text.hasPrefix("Cathedral Rock"))
        #expect(snippet.text.hasSuffix("…"))
        #expect(highlighted(snippet) == ["Cathedral"])
        #expect(snippet.placeName == nil)
    }

    @Test func matchInTheMiddleIsShownWithLeadingContext() {
        let snippet = SearchSnippet(body: long, placeName: nil, query: SearchQuery("scramble"))

        #expect(snippet.text.hasPrefix("…"))
        #expect(snippet.text.contains("hands-and-feet scramble"))
        #expect(highlighted(snippet) == ["scramble"])
        // Starts at a word, and the line breaks are gone.
        #expect(!snippet.text.contains("\n"))
        #expect(snippet.text.dropFirst().first?.isWhitespace == false)
        #expect(snippet.text.count <= SearchSnippet.maximumLength + 2)
    }

    @Test func matchAtTheEndKeepsTheMatch() {
        let snippet = SearchSnippet(body: long, placeName: nil, query: SearchQuery("butte"))

        #expect(snippet.text.hasPrefix("…"))
        #expect(snippet.text.hasSuffix("Courthouse Butte first."))
        #expect(highlighted(snippet) == ["Butte"])
    }

    @Test func shortBodiesAreShownWhole() {
        let body = "Elote Cafe. Get the fire-roasted corn."
        let snippet = SearchSnippet(body: body, placeName: nil, query: SearchQuery("corn cafe"))

        #expect(snippet.text == body)
        #expect(highlighted(snippet) == ["Cafe", "corn"])
    }

    @Test func placeNameOnlyMatchShowsTheStartAndTheHighlightedPlace() {
        let snippet = SearchSnippet(
            body: long, placeName: "Cathedral Rock Trailhead", query: SearchQuery("rock"))
        #expect(snippet.placeName == "Cathedral Rock Trailhead")

        let placeOnly = SearchSnippet(
            body: "Devil’s Bridge from the Dry Creek Rd lot.",
            placeName: "Devil’s Bridge Trailhead",
            query: SearchQuery("trailhead")
        )
        #expect(placeOnly.text == "Devil’s Bridge from the Dry Creek Rd lot.")
        #expect(placeOnly.highlights.isEmpty)
        #expect(placeOnly.placeName == "Devil’s Bridge Trailhead")
        #expect(
            placeOnly.placeNameHighlights.map { String("Devil’s Bridge Trailhead"[$0]) }
                == ["Trailhead"])
    }
}

// MARK: Results

@MainActor
struct SearchResultsTests {
    private let container: ModelContainer
    private let context: ModelContext
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

    init() throws {
        container = try ModelContainerFactory.makeInMemory()
        context = ModelContext(container)
    }

    private func topic(_ title: String) -> Topic {
        let topic = Topic(title: title, createdAt: base)
        context.insert(topic)
        return topic
    }

    @discardableResult
    private func entry(_ body: String, in topic: Topic, daysAgo: Double) -> Entry {
        let entry = Entry(
            body: body, date: base.addingTimeInterval(-daysAgo * 86_400), topic: topic)
        context.insert(entry)
        return entry
    }

    private func results(_ text: String) throws -> SearchResults {
        try context.save()
        return try EntrySearch(context: context).results(for: SearchQuery(text))
    }

    @Test func topicsMatchByTitleInRecentActivityOrder() throws {
        let older = topic("Trail notes")
        let newer = topic("Trail log")
        topic("Kitchen")
        entry("a", in: older, daysAgo: 10)
        entry("b", in: newer, daysAgo: 1)

        #expect(try results("trail").topics == [newer, older])
    }

    @Test func entriesAreNewestFirst() throws {
        let hikes = topic("Hikes")
        let middle = entry("Mesa loop", in: hikes, daysAgo: 5)
        let newest = entry("Mesa again", in: hikes, daysAgo: 1)
        let oldest = entry("First mesa", in: hikes, daysAgo: 9)

        #expect(try results("mesa").entries == [newest, middle, oldest])
    }

    @Test func entriesAreCappedAtTheLimit() throws {
        let hikes = topic("Hikes")
        for day in 0..<(SearchResults.entryLimit + 5) {
            entry("Walk \(day)", in: hikes, daysAgo: Double(day))
        }

        let found = try results("walk")
        #expect(found.entries.count == SearchResults.entryLimit)
        #expect(found.isCapped)
        #expect(found.entries.first?.body == "Walk 0")

        #expect(try !results("walk 7").isCapped)
    }

    @Test func onlyLiveEntriesAppearAndArchivedOnesDo() throws {
        let live = topic("Live")
        let archived = topic("Old trips")
        archived.isArchived = true
        let trashedTopic = topic("Gone")
        trashedTopic.deletedAt = base

        let kept = entry("Ridge walk", in: live, daysAgo: 1)
        let trashed = entry("Ridge walk, trashed", in: live, daysAgo: 2)
        trashed.deletedAt = base
        let inArchived = entry("Ridge walk, archived", in: archived, daysAgo: 3)
        entry("Ridge walk, topic trashed", in: trashedTopic, daysAgo: 4)

        let found = try results("ridge")
        #expect(found.entries == [kept, inArchived])

        // Trashed topics never match by title either.
        #expect(try results("gone").topics.isEmpty)
        #expect(try results("old trips").topics == [archived])
    }

    @Test func fetchIgnoresAccentsInEitherDirection() throws {
        let food = topic("Food")
        let accented = entry("Lunch at the Café Pino.", in: food, daysAgo: 1)
        let plain = entry("Cafe con leche.", in: food, daysAgo: 2)

        #expect(try results("cafe").entries == [accented, plain])
        #expect(try results("CAFÉ").entries == [accented, plain])
    }

    @Test func belowTheMinimumLengthNothingIsSearched() throws {
        let food = topic("Food")
        entry("a b c", in: food, daysAgo: 1)

        let found = try results("a")
        #expect(found.isEmpty)
    }
}

// MARK: Fetch path, seeded

@MainActor
struct SearchFetchTests {
    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        container = try SampleData.makeContainer()
        context = container.mainContext
    }

    private func search(_ text: String) throws -> SearchResults {
        try EntrySearch(context: context).results(for: SearchQuery(text))
    }

    private func bodies(_ text: String) throws -> [String] {
        try search(text).entries.map { String($0.body.prefix(20)) }
    }

    @Test func placeNameOnlyMatchesAreFound() throws {
        // Devil’s Bridge mentions no trailhead; its place name does.
        let found = try bodies("trailhead")
        #expect(found.contains { $0.hasPrefix("Devil’s Bridge") })
        #expect(found.contains { $0.hasPrefix("Cathedral Rock") })
        #expect(found.contains { $0.hasPrefix("Bear Rocks") })
    }

    @Test func wordsSplitBetweenTextAndPlaceNameMatch() throws {
        #expect(try bodies("corn sedona") == ["Elote Cafe. Get the "])
    }

    @Test func topicTitleAndPlaceNamesTogether() throws {
        let found = try search("sedona")
        #expect(found.topics.map(\.title) == ["Sedona trip"])
        #expect(found.entries.map { String($0.body.prefix(5)) } == ["Elote", "Arriv"])
    }

    @Test func trashedEntriesAndTrashedTopicsNeverAppear() throws {
        // "Red Rock Pass receipt." is trashed; Kitchen remodel is a trashed topic.
        #expect(try search("receipt").isEmpty)
        #expect(try search("countertop").isEmpty)
        #expect(try search("kitchen").topics.isEmpty)
    }

    @Test func archivedTopicsEntriesAppear() throws {
        let found = try search("fog")
        #expect(found.entries.count == 1)
        #expect(found.entries.first?.topic?.isArchived == true)
    }

    @Test func multiWordAndPunctuatedQueries() throws {
        #expect(try bodies("padron").isEmpty)  // trashed
        #expect(try search("hemingway fuente").entries.count == 1)
        #expect(try bodies("devils").isEmpty)  // the apostrophe is part of the word
        #expect(try bodies("Devil’s bridge").count == 1)
    }
}
