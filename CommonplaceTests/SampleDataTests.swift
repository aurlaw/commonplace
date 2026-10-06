import Foundation
import SwiftData
import Testing

@testable import Commonplace

@MainActor
struct SampleDataTests {
    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        container = try SampleData.makeContainer()
        context = container.mainContext
    }

    @Test func seedsIntoAnInMemoryContainerWithCloudKitDisabled() {
        for configuration in container.configurations {
            #expect(configuration.isStoredInMemoryOnly)
            #expect(configuration.cloudKitContainerIdentifier == nil)
        }
    }

    @Test func seedsSixTopicsWithOneArchivedAndOneTrashed() throws {
        let topics = try context.fetch(FetchDescriptor<Topic>())

        #expect(
            Set(topics.map(\.title)) == [
                "Stoic practice", "Sedona trip", "Cigars", "App ideas", "Dolly Sods",
                "Kitchen remodel",
            ]
        )
        #expect(topics.filter(\.isArchived).map(\.title) == ["Dolly Sods"])
        #expect(topics.filter(\.isTrashed).map(\.title) == ["Kitchen remodel"])
        #expect(topics.filter { $0.isArchived && $0.isTrashed }.isEmpty)
    }

    @Test func topicsUseTheDesignColors() throws {
        let topics = try context.fetch(FetchDescriptor<Topic>())
        let colors = Dictionary(uniqueKeysWithValues: topics.map { ($0.title, $0.color) })

        #expect(
            colors == [
                "Stoic practice": .indigo, "Sedona trip": .orange, "Cigars": .brown,
                "App ideas": .purple, "Dolly Sods": .green, "Kitchen remodel": .teal,
            ]
        )
    }

    @Test func seedsThreeTrashedEntriesInLiveTopics() throws {
        let trashed = try context.fetch(
            FetchDescriptor<Entry>(predicate: #Predicate { $0.deletedAt != nil })
        )

        #expect(
            Set(trashed.compactMap { $0.topic?.title }) == ["App ideas", "Cigars", "Sedona trip"]
        )
        #expect(trashed.count == 3)
        #expect(trashed.allSatisfy { $0.topic?.isTrashed == false })
        let receipt = try #require(trashed.first { $0.body == "Red Rock Pass receipt." })
        #expect(receipt.photos?.count == 1)
    }

    @Test func sedonaHasSixEntriesWithTheDesignPhotoCounts() throws {
        let sedona = try #require(topic("Sedona trip"))
        let entries = sedona.liveEntries.sorted { $0.date > $1.date }

        #expect(entries.count == 6)
        #expect(entries.map { $0.sortedPhotos.count } == [3, 0, 5, 6, 1, 0])
        #expect(
            sedona.summary
                == "Five days in red rock country, Sep 30 – Oct 4. Trail notes, sunrises, and where we ate."
        )
    }

    @Test func sedonaCathedralRockEntryHasThreeParagraphs() throws {
        let sedona = try #require(topic("Sedona trip"))
        let entry = try #require(sedona.liveEntries.first { $0.sortedPhotos.count == 6 })

        #expect(entry.date == SampleData.date(2026, 10, 2, 6, 10))
        #expect(entry.body.components(separatedBy: "\n\n").count == 3)
        #expect(entry.body.hasPrefix("Cathedral Rock at first light."))
    }

    @Test func stoicPracticeIncludesTheComposerSampleText() throws {
        let stoic = try #require(topic("Stoic practice"))

        #expect(stoic.liveEntries.contains { $0.body.hasPrefix("Morning. In my control today:") })
    }

    @Test func photosHaveImageAndThumbnailDataAndExplicitOrder() throws {
        let photos = try context.fetch(FetchDescriptor<Photo>())

        #expect(photos.count == 18)
        #expect(photos.allSatisfy { $0.imageData?.isEmpty == false })
        #expect(photos.allSatisfy { $0.thumbnailData?.isEmpty == false })
        let entries = try context.fetch(FetchDescriptor<Entry>())
        for entry in entries {
            #expect(entry.sortedPhotos.map(\.order) == Array(0..<entry.sortedPhotos.count))
        }
    }

    @Test func datesAreFixedInSeptemberAndOctober2026ForSedona() throws {
        let sedona = try #require(topic("Sedona trip"))
        let range = SampleData.date(2026, 9, 30, 0, 0)...SampleData.date(2026, 10, 4, 23, 59)

        #expect(sedona.liveEntries.allSatisfy { range.contains($0.date) })
    }

    @Test func recentActivityOrderMatchesTheDesign() throws {
        let live = try context.fetch(
            FetchDescriptor<Topic>(predicate: #Predicate { $0.deletedAt == nil && !$0.isArchived })
        )

        #expect(
            Topic.sortedByRecentActivity(live).map(\.title)
                == ["Stoic practice", "Sedona trip", "Cigars", "App ideas"]
        )
        let labels = Topic.sortedByRecentActivity(live).compactMap(\.lastEntryDate).map {
            EntryTimeline.lastEntryLabel(for: $0, now: SampleData.now)
        }
        #expect(labels.prefix(2) == ["Today", "Yesterday"])
    }

    private func topic(_ title: String) -> Topic? {
        try? context.fetch(FetchDescriptor<Topic>(predicate: #Predicate { $0.title == title }))
            .first
    }
}
