import Foundation
import SwiftData
import Testing

@testable import Commonplace

@MainActor
struct LastUsedTopicTests {
    private let container: ModelContainer
    private let context: ModelContext
    private let cigars: Topic
    private let sedona: Topic
    private let stoic: Topic

    /// Stoic practice has the most recent entry, so it is the fallback.
    init() throws {
        container = try ModelContainerFactory.makeInMemory()
        context = ModelContext(container)
        cigars = Topic(title: "Cigars", createdAt: Date(timeIntervalSinceReferenceDate: 100))
        sedona = Topic(title: "Sedona trip", createdAt: Date(timeIntervalSinceReferenceDate: 200))
        stoic = Topic(title: "Stoic practice", createdAt: Date(timeIntervalSinceReferenceDate: 50))
        for topic in [cigars, sedona, stoic] {
            context.insert(topic)
        }
        context.insert(
            Entry(body: "Morning.", date: Date(timeIntervalSinceReferenceDate: 900), topic: stoic)
        )
        try context.save()
    }

    private var topics: [Topic] { [cigars, sedona, stoic] }

    @Test func storedValueRoundTripsToTheSameTopic() throws {
        let stored = try #require(LastUsedTopic.encode(cigars))

        #expect(LastUsedTopic.decode(stored) == cigars.persistentModelID)
        #expect(LastUsedTopic.decode(stored) != sedona.persistentModelID)
    }

    @Test func resolvesTheStoredTopicWhenItIsLive() throws {
        let stored = try #require(LastUsedTopic.encode(cigars))

        #expect(LastUsedTopic.resolve(stored: stored, among: topics) === cigars)
    }

    @Test func resolvesAcrossContextsOfTheSameStore() throws {
        let stored = try #require(LastUsedTopic.encode(cigars))
        let otherContext = ModelContext(container)
        let fetched = try otherContext.fetch(FetchDescriptor<Topic>())

        #expect(LastUsedTopic.resolve(stored: stored, among: fetched)?.title == "Cigars")
    }

    @Test func fallsBackWhenTheStoredTopicIsArchived() throws {
        let stored = try #require(LastUsedTopic.encode(cigars))
        cigars.isArchived = true

        #expect(LastUsedTopic.resolve(stored: stored, among: topics) === stoic)
    }

    @Test func fallsBackWhenTheStoredTopicIsTrashed() throws {
        let stored = try #require(LastUsedTopic.encode(cigars))
        cigars.deletedAt = .now

        #expect(LastUsedTopic.resolve(stored: stored, among: topics) === stoic)
    }

    @Test func fallsBackWhenTheStoredTopicIsMissing() throws {
        let stored = try #require(LastUsedTopic.encode(cigars))

        #expect(LastUsedTopic.resolve(stored: stored, among: [sedona, stoic]) === stoic)
    }

    @Test func fallsBackWithNothingStored() {
        #expect(LastUsedTopic.resolve(stored: nil, among: topics) === stoic)
    }

    @Test func fallsBackWhenTheStoredValueIsNotAnIdentifier() {
        #expect(LastUsedTopic.resolve(stored: Data("not json".utf8), among: topics) === stoic)
        #expect(LastUsedTopic.resolve(stored: Data(), among: topics) === stoic)
    }

    @Test func fallbackSkipsArchivedAndTrashedTopics() {
        stoic.isArchived = true
        sedona.deletedAt = .now

        #expect(LastUsedTopic.resolve(stored: nil, among: topics) === cigars)
    }

    @Test func resolvesToNothingWhenNoTopicIsUsable() throws {
        let stored = try #require(LastUsedTopic.encode(cigars))
        for topic in topics {
            topic.isArchived = true
        }

        #expect(LastUsedTopic.resolve(stored: stored, among: topics) == nil)
        #expect(LastUsedTopic.resolve(stored: nil, among: []) == nil)
    }
}
