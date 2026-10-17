import Foundation
import FoundationModels
import Testing

@testable import Commonplace

// MARK: Chunking

struct CleanUpChunkTests {
    private func chunks(_ pieces: [CleanUpChunks.Piece]) -> [String] {
        pieces.compactMap { if case .chunk(let text) = $0 { text } else { nil } }
    }

    @Test func splitsAtParagraphsAndBulletBoundaries() {
        let body = "so um we left early\n\nnext time:\n- gloves\n- a weekday\n\n\nthe end"
        let pieces = CleanUpChunks.split(body)

        #expect(
            chunks(pieces) == [
                "so um we left early", "next time:", "- gloves\n- a weekday", "the end",
            ])
        #expect(CleanUpChunks.join(pieces) == body)
    }

    @Test func rejoinPreservesSeparatorsExactly() {
        for body in [
            "", "one", "\n\nleading and trailing\n\n", "a\n \t\nb", "line one\nline two",
            "- a\nb\n- c", "trailing newline\n",
        ] {
            #expect(
                CleanUpChunks.join(CleanUpChunks.split(body)) == body, "\(body.debugDescription)")
        }
    }

    @Test func linesOfOneParagraphStayTogether() {
        #expect(chunks(CleanUpChunks.split("line one\nline two")) == ["line one\nline two"])
    }

    @Test func anOversizedParagraphSplitsAtSentences() {
        let paragraph = "First sentence here. Second one is here. Third comes last."
        let pieces = CleanUpChunks.split(paragraph, budget: 25)

        #expect(
            chunks(pieces) == ["First sentence here.", "Second one is here.", "Third comes last."])
        #expect(CleanUpChunks.join(pieces) == paragraph)
    }

    @Test func sentencesArePackedUpToTheBudget() {
        let paragraph = "One. Two. Three. Four."
        let pieces = CleanUpChunks.split(paragraph, budget: 10)

        #expect(chunks(pieces) == ["One. Two.", "Three.", "Four."])
        #expect(CleanUpChunks.join(pieces) == paragraph)
    }

    @Test func aSentenceOverTheBudgetSplitsAtSpaces() {
        let sentence = "and then we walked and walked and walked"
        let pieces = CleanUpChunks.split(sentence, budget: 15)

        #expect(chunks(pieces).allSatisfy { $0.count <= 15 })
        #expect(CleanUpChunks.join(pieces) == sentence)
    }
}

// MARK: Post-check

struct CleanUpCheckTests {
    private let original =
        "so um we had dinner at [Elote](https://elotecafe.com) and it was **great** see https://example.com/menu"

    @Test func aValidEditIsAccepted() {
        let cleaned =
            "So we had dinner at [Elote](https://elotecafe.com), and it was **great**. See https://example.com/menu."
        #expect(CleanUpCheck.accepts(original: original, cleaned: cleaned))
    }

    @Test func aChangedRemovedOrReorderedURLIsRejected() {
        let changed =
            "So we had dinner at [Elote](https://elote.com), and it was **great**. See https://example.com/menu."
        let removed =
            "So we had dinner at Elote, and it was **great**. See https://example.com/menu."
        let reordered =
            "See https://example.com/menu. So we had dinner at [Elote](https://elotecafe.com), and it was **great**."
        #expect(!CleanUpCheck.accepts(original: original, cleaned: changed))
        #expect(!CleanUpCheck.accepts(original: original, cleaned: removed))
        #expect(!CleanUpCheck.accepts(original: original, cleaned: reordered))
    }

    @Test func unbalancedOrAddedEmphasisIsRejected() {
        let unbalanced =
            "So we had dinner at [Elote](https://elotecafe.com), and it was **great. See https://example.com/menu."
        let added =
            "So we had **dinner** at [Elote](https://elotecafe.com), and it was **great**. See https://example.com/menu."
        #expect(!CleanUpCheck.accepts(original: original, cleaned: unbalanced))
        #expect(!CleanUpCheck.accepts(original: original, cleaned: added))
    }

    @Test func aLostBulletLineIsRejected() {
        let list = "- gloves for the slickrock\n- a weekday"
        #expect(
            CleanUpCheck.accepts(original: list, cleaned: "- Gloves for the slickrock\n- A weekday")
        )
        #expect(
            !CleanUpCheck.accepts(original: list, cleaned: "Gloves for the slickrock and a weekday")
        )
    }

    @Test func lengthOutOfRangeIsRejected() {
        let text = "we walked up to the saddle and sat for twenty minutes watching the light"
        #expect(!CleanUpCheck.accepts(original: text, cleaned: "We walked."))
        #expect(!CleanUpCheck.accepts(original: text, cleaned: text + " " + text))
        #expect(!CleanUpCheck.accepts(original: text, cleaned: "   "))
    }
}

// MARK: Runner

struct CleanUpRunnerTests {
    @Test func everyChunkIsCleanedAndJoinedWithTheOriginalSeparators() async {
        let body = "we left early\n\n- um gloves\n- a weekday"
        let outcome = await CleanUpRunner.run(body, with: FakeTextCleaner())

        #expect(outcome.text == "We left early.\n\n- gloves\n- a weekday.")
        #expect(outcome.cleanedCount == 2)
        #expect(outcome.failedCount == 0)
        #expect(outcome.message == nil)
    }

    @Test func partialFailureKeepsTheFailedChunksInOrder() async {
        let cleaner = FakeTextCleaner(transform: { text in
            if text.hasPrefix("two") {
                throw TextCleanerError.refused
            }
            return try FakeTextCleaner.tidy(text)
        })
        let body = "one here\n\ntwo here\n\nthree here"
        let outcome = await CleanUpRunner.run(body, with: cleaner)

        #expect(outcome.text == "One here.\n\ntwo here\n\nThree here.")
        #expect(outcome.cleanedCount == 2)
        #expect(outcome.failedCount == 1)
        #expect(outcome.message == "Some text couldn’t be cleaned up")
    }

    @Test func aRejectedResultKeepsTheOriginal() async {
        let cleaner = FakeTextCleaner(transform: { _ in "A summary." })
        let body = "we walked up to the saddle and sat for twenty minutes watching the light"
        let outcome = await CleanUpRunner.run(body, with: cleaner)

        #expect(outcome.text == body)
        #expect(!outcome.changed)
        #expect(outcome.message == "No changes")
    }

    @Test func nothingToChangeIsNoChanges() async {
        let cleaner = FakeTextCleaner(transform: { $0 })
        let outcome = await CleanUpRunner.run("Already clean.", with: cleaner)

        #expect(outcome.text == "Already clean.")
        #expect(outcome.failedCount == 0)
        #expect(outcome.message == "No changes")
    }

    @Test func anOverflowIsRetriedSmallerOnceThenGivenUp() async {
        // Overflows on anything longer than one sentence.
        let cleaner = FakeTextCleaner(transform: { text in
            if text.count > 30 {
                throw TextCleanerError.contextOverflow
            }
            return try FakeTextCleaner.tidy(text)
        })
        // Capitalized: sentence detection (ICU) doesn't break before a lowercase word.
        let body = "First sentence is here. Second sentence is here"
        let outcome = await CleanUpRunner.run(body, with: cleaner, budget: 1_000)
        #expect(outcome.text == "First sentence is here. Second sentence is here.")
        #expect(outcome.cleanedCount == 1)

        let alwaysOverflows = FakeTextCleaner(transform: { _ in
            throw TextCleanerError.contextOverflow
        })
        let unchanged = await CleanUpRunner.run(body, with: alwaysOverflows)
        #expect(unchanged.text == body)
        #expect(unchanged.message == "No changes")
    }
}

// MARK: Draft

@MainActor
struct CleanUpDraftTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func outcome(_ text: String) -> CleanUpOutcome {
        CleanUpOutcome(text: text, cleanedCount: 1, failedCount: 0)
    }

    @Test func cleanUpReplacesTheBodyAndRevertRestoresItExactly() {
        var draft = EntryDraft(mode: .newFromList, now: now)
        draft.body = "um so we left"
        let original = draft

        let started = draft.beginCleanUp()
        #expect(started)
        #expect(draft.isCleaning)
        #expect(!draft.isDirty(comparedTo: original))  // cleaning alone isn't a change

        draft.finishCleanUp(outcome("So we left."))
        #expect(draft.body == "So we left.")
        #expect(draft.canRevertCleanUp)
        #expect(draft.isDirty(comparedTo: original))

        draft.revertCleanUp()
        #expect(draft.body == "um so we left")
        #expect(draft.cleanUp == .idle)
        #expect(!draft.isDirty(comparedTo: original))
    }

    @Test func typingAfterCleanUpKeepsTheTextAndRetiresRevert() {
        var draft = EntryDraft(mode: .newFromList, now: now)
        draft.body = "um so we left"
        draft.beginCleanUp()
        draft.finishCleanUp(outcome("So we left."))

        draft.bodyDidChange()  // the clean-up's own change
        #expect(draft.canRevertCleanUp)

        draft.body += " Early."
        draft.bodyDidChange()
        #expect(draft.body == "So we left. Early.")
        #expect(!draft.canRevertCleanUp)
        draft.revertCleanUp()
        #expect(draft.body == "So we left. Early.")
    }

    @Test func cancelKeepsTheOriginal() {
        var draft = EntryDraft(mode: .newFromList, now: now)
        draft.body = "um so we left"
        draft.beginCleanUp()

        draft.cancelCleanUp()
        draft.finishCleanUp(outcome("So we left."))  // arrives late

        #expect(draft.body == "um so we left")
        #expect(draft.cleanUp == .idle)
    }

    @Test func noChangesLeavesTheBodyAlone() {
        var draft = EntryDraft(mode: .newFromList, now: now)
        draft.body = "Clean."
        draft.beginCleanUp()

        draft.finishCleanUp(CleanUpOutcome(text: "Clean.", cleanedCount: 0, failedCount: 0))

        #expect(draft.body == "Clean.")
        #expect(draft.cleanUp == .idle)
    }

    @Test func cleanUpNeedsTextAndNoDictation() {
        var draft = EntryDraft(mode: .newFromList, now: now)
        draft.body = "  \n"
        let started = draft.beginCleanUp()
        #expect(!started)

        draft.body = "Some text"
        draft.beginDictation(at: nil)
        #expect(!draft.canCleanUp)
        draft.endDictation()
        #expect(draft.canCleanUp)
    }
}

// MARK: Availability

struct TextCleanerAvailabilityTests {
    @Test func eachReasonMapsToUnavailable() {
        #expect(FoundationModelsCleaner.map(.available) == .available)
        #expect(
            FoundationModelsCleaner.map(.unavailable(.deviceNotEligible))
                == .unavailable(.deviceNotEligible))
        #expect(
            FoundationModelsCleaner.map(.unavailable(.appleIntelligenceNotEnabled))
                == .unavailable(.appleIntelligenceOff))
        #expect(
            FoundationModelsCleaner.map(.unavailable(.modelNotReady))
                == .unavailable(.modelDownloading))
    }

    @Test func onlyAvailableShowsTheButton() {
        let reasons: [TextCleanerUnavailable] = [
            .deviceNotEligible, .appleIntelligenceOff, .modelDownloading, .other,
        ]
        for reason in reasons {
            #expect(FakeTextCleaner(availability: .unavailable(reason)).availability != .available)
        }
        #expect(FakeTextCleaner().availability == .available)
    }
}
