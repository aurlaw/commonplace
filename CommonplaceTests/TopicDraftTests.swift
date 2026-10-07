import Foundation
import SwiftData
import Testing

@testable import Commonplace

@MainActor
struct TopicDraftTests {
    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        container = try ModelContainerFactory.makeInMemory()
        context = ModelContext(container)
    }

    // MARK: Trimming and validation

    @Test func trimmedRemovesSurroundingWhitespaceFromTitleAndSummary() {
        let draft = TopicDraft(
            title: "  Reading notes \n", summary: "\t Books and essays.  ", color: .teal)

        #expect(
            draft.trimmed
                == TopicDraft(title: "Reading notes", summary: "Books and essays.", color: .teal))
    }

    @Test func trimmedKeepsInnerWhitespace() {
        #expect(TopicDraft(title: " Sedona  trip ").trimmed.title == "Sedona  trip")
    }

    @Test func isValidRequiresANonEmptyTrimmedTitle() {
        #expect(!TopicDraft(title: "").isValid)
        #expect(!TopicDraft(title: "   ").isValid)
        #expect(!TopicDraft(title: " \n\t ").isValid)
        #expect(!TopicDraft(title: "", summary: "Only a summary").isValid)
        #expect(TopicDraft(title: "Cigars").isValid)
        #expect(TopicDraft(title: "  Cigars  ").isValid)
    }

    // MARK: Writing to models

    @Test func makeTopicUsesTrimmedValuesAndDefaults() throws {
        let draft = TopicDraft(title: "  Reading notes ", summary: " Books. ", color: .teal)

        let topic = draft.makeTopic()
        context.insert(topic)
        try context.save()

        let stored = try #require(try context.fetch(FetchDescriptor<Topic>()).first)
        #expect(stored.title == "Reading notes")
        #expect(stored.summary == "Books.")
        #expect(stored.color == .teal)
        #expect(stored.isArchived == false)
        #expect(stored.deletedAt == nil)
        #expect(stored.capturesLocation == false)
        #expect(stored.entries?.isEmpty == true)
    }

    @Test func makeTopicAllowsAnEmptySummary() {
        let topic = TopicDraft(title: "Cigars", summary: "   ").makeTopic()

        #expect(topic.summary == "")
    }

    @Test func applyUpdatesAnExistingTopicAndLeavesTheRestAlone() throws {
        let createdAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let topic = Topic(title: "Sedona", summary: "Old", color: .orange, createdAt: createdAt)
        topic.isArchived = true
        context.insert(topic)
        let entry = Entry(body: "Arrived.", topic: topic)
        context.insert(entry)
        try context.save()

        TopicDraft(title: " Sedona trip ", summary: " Red rock country. ", color: .red).apply(
            to: topic)
        try context.save()

        #expect(topic.title == "Sedona trip")
        #expect(topic.summary == "Red rock country.")
        #expect(topic.color == .red)
        #expect(topic.colorName == "red")
        #expect(topic.isArchived)
        #expect(topic.createdAt == createdAt)
        #expect(topic.entries?.count == 1)
        #expect(try context.fetchCount(FetchDescriptor<Topic>()) == 1)
    }

    @Test func draftFromEditModeCopiesTheTopic() {
        let topic = Topic(title: "Cigars", summary: "Tasting notes.", color: .brown)
        context.insert(topic)

        #expect(
            TopicDraft(mode: .edit(topic))
                == TopicDraft(title: "Cigars", summary: "Tasting notes.", color: .brown)
        )
        #expect(TopicDraft(mode: .new) == TopicDraft())
    }

    // MARK: Dirty detection

    @Test func pristineDraftIsNotDirty() {
        let original = TopicDraft(title: "Cigars", summary: "Tasting notes.", color: .brown)

        #expect(!original.isDirty(comparedTo: original))
        #expect(!TopicDraft().isDirty(comparedTo: TopicDraft()))
    }

    @Test func changingAnyFieldIsDirty() {
        let original = TopicDraft(title: "Cigars", summary: "Tasting notes.", color: .brown)

        var draft = original
        draft.title = "Cigar notes"
        #expect(draft.isDirty(comparedTo: original))

        draft = original
        draft.summary = ""
        #expect(draft.isDirty(comparedTo: original))

        draft = original
        draft.color = .red
        #expect(draft.isDirty(comparedTo: original))
    }

    @Test func whitespaceOnlyChangesAreNotDirty() {
        let original = TopicDraft(title: "Cigars", summary: "Tasting notes.", color: .brown)
        var draft = original
        draft.title = "Cigars  "
        draft.summary = " Tasting notes."

        #expect(!draft.isDirty(comparedTo: original))
        #expect(!TopicDraft(title: "   ").isDirty(comparedTo: TopicDraft()))
    }

    @Test func revertingAChangeIsNoLongerDirty() {
        let original = TopicDraft(title: "Cigars")
        var draft = original
        draft.title = "Cigar"
        draft.title = "Cigars"

        #expect(!draft.isDirty(comparedTo: original))
    }
}
