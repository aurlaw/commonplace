import Foundation
import SwiftData
import Testing

@testable import Commonplace

@MainActor
struct TopicListTests {
    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        container = try ModelContainerFactory.makeInMemory()
        context = ModelContext(container)
    }

    // MARK: sortedByName

    @Test func sortedByNameIsCaseAndNumberAware() {
        let topics = ["Trip 10", "apple", "Trip 2", "Banana", "trip 1", "cherry"].map { topic($0) }

        #expect(
            Topic.sortedByName(topics).map(\.title)
                == ["apple", "Banana", "cherry", "trip 1", "Trip 2", "Trip 10"]
        )
    }

    @Test func sortedByNameBreaksTiesByCreatedAt() {
        let newer = topic("Cigars", createdAt: 300)
        let oldest = topic("Cigars", createdAt: 100)
        let middle = topic("Cigars", createdAt: 200)

        let sorted = Topic.sortedByName([newer, oldest, middle])

        #expect(sorted.map(\.createdAt.timeIntervalSinceReferenceDate) == [100, 200, 300])
    }

    // MARK: TopicSort

    @Test func topicSortRoundTripsThroughItsRawValue() {
        for sort in TopicSort.allCases {
            #expect(TopicSort(storedValue: sort.rawValue) == sort)
        }
        #expect(TopicSort.recentActivity.rawValue == "recentActivity")
        #expect(TopicSort.name.rawValue == "name")
    }

    @Test func topicSortFallsBackToRecentActivityForUnknownValues() {
        #expect(TopicSort(storedValue: "manual") == .recentActivity)
        #expect(TopicSort(storedValue: "") == .recentActivity)
        #expect(TopicSort(storedValue: "Name") == .recentActivity)
    }

    @Test func topicSortAppliesTheMatchingOrder() {
        let quiet = topic("Alpha", createdAt: 100)
        let busy = topic("Zulu", createdAt: 50)
        context.insert(
            Entry(body: "Recent", date: Date(timeIntervalSinceReferenceDate: 900), topic: busy))

        #expect(TopicSort.recentActivity.sorted([quiet, busy]).map(\.title) == ["Zulu", "Alpha"])
        #expect(TopicSort.name.sorted([busy, quiet]).map(\.title) == ["Alpha", "Zulu"])
    }

    // MARK: Sections

    @Test func archivingMovesATopicFromTheLiveToTheArchivedSection() throws {
        let cigars = topic("Cigars")
        let sedona = topic("Sedona trip")
        try context.save()

        var sections = TopicListSections(topics: try liveTopics(), sort: .name)
        #expect(sections.live.map(\.title) == ["Cigars", "Sedona trip"])
        #expect(sections.archived.isEmpty)

        sedona.isArchived = true
        try context.save()

        sections = TopicListSections(topics: try liveTopics(), sort: .name)
        #expect(sections.live.map(\.title) == ["Cigars"])
        #expect(sections.archived.map(\.title) == ["Sedona trip"])

        sedona.isArchived = false
        cigars.isArchived = true
        try context.save()

        sections = TopicListSections(topics: try liveTopics(), sort: .name)
        #expect(sections.live.map(\.title) == ["Sedona trip"])
        #expect(sections.archived.map(\.title) == ["Cigars"])
    }

    @Test func bothSectionsUseTheChosenSort() {
        let topics = [
            topic("Bravo", createdAt: 300),
            topic("Alpha", createdAt: 100),
            archived(topic("Yankee", createdAt: 400)),
            archived(topic("X-ray", createdAt: 200)),
        ]

        let byName = TopicListSections(topics: topics, sort: .name)
        #expect(byName.live.map(\.title) == ["Alpha", "Bravo"])
        #expect(byName.archived.map(\.title) == ["X-ray", "Yankee"])

        let byActivity = TopicListSections(topics: topics, sort: .recentActivity)
        #expect(byActivity.live.map(\.title) == ["Bravo", "Alpha"])
        #expect(byActivity.archived.map(\.title) == ["Yankee", "X-ray"])
    }

    // MARK: Helpers

    private func topic(_ title: String, createdAt: TimeInterval = 0) -> Topic {
        let topic = Topic(title: title, createdAt: Date(timeIntervalSinceReferenceDate: createdAt))
        context.insert(topic)
        return topic
    }

    private func archived(_ topic: Topic) -> Topic {
        topic.isArchived = true
        return topic
    }

    /// The same filter the topics list queries with.
    private func liveTopics() throws -> [Topic] {
        try context.fetch(FetchDescriptor<Topic>(predicate: #Predicate { $0.deletedAt == nil }))
    }
}
