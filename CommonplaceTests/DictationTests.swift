import Foundation
import SwiftData
import Testing

@testable import Commonplace

// MARK: Spacing

struct DictationSpacingTests {
    @Test func insertsAtTheStartWithASpaceAfter() {
        let splice = DictationSpacing.splice("Today", into: "we hiked.", at: 0)

        #expect(splice.result == "Today we hiked.")
        #expect(splice.insertionPoint == 5)
    }

    @Test func insertsMidParagraphWithSpacesOnBothSides() {
        let body = "The brown fox."
        let splice = DictationSpacing.splice("quick", into: body, at: 3)

        #expect(splice.result == "The quick brown fox.")
        #expect(splice.insertionPoint == 9)
    }

    @Test func insertsAfterASpaceWithoutAddingAnother() {
        let splice = DictationSpacing.splice("quick", into: "The brown", at: 4)

        #expect(splice.result == "The quick brown")
    }

    @Test func appendsAtTheEndWithALeadingSpace() {
        let body = "Back at the car."
        let splice = DictationSpacing.splice("Ninety minutes.", into: body, at: body.count)

        #expect(splice.result == "Back at the car. Ninety minutes.")
        #expect(splice.insertionPoint == splice.result.count)
    }

    @Test func noSpaceInAnEmptyBodyOrAfterANewline() {
        #expect(DictationSpacing.splice("Hello", into: "", at: 0).result == "Hello")
        #expect(DictationSpacing.splice("Hello", into: "Hi\n", at: 3).result == "Hi\nHello")
    }

    @Test func noSpaceBeforeClosingPunctuationOrAfterAnOpeningBracket() {
        #expect(DictationSpacing.splice("ok", into: "(", at: 1).result == "(ok")
        #expect(DictationSpacing.splice("steep", into: "It was.", at: 6).result == "It was steep.")
        #expect(DictationSpacing.splice(", then", into: "Up", at: 2).result == "Up, then")
    }

    @Test func trimsTheSegmentAndIgnoresEmptyOnes() {
        #expect(DictationSpacing.splice("  word \n", into: "A", at: 1).result == "A word")
        let empty = DictationSpacing.splice("   ", into: "A", at: 1)
        #expect(empty.result == "A")
        #expect(empty.inserted.isEmpty)
    }
}

// MARK: Draft

@MainActor
struct DictationDraftTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func draft(body: String = "") -> EntryDraft {
        var draft = EntryDraft(mode: .newFromList, now: now)
        draft.body = body
        return draft
    }

    @Test func multipleFinalsAdvanceTheInsertionPoint() {
        var draft = draft(body: "Start. End.")
        draft.beginDictation(at: 6)

        draft.insertFinal("One.")
        draft.insertFinal("Two.")

        #expect(draft.body == "Start. One. Two. End.")
        #expect(draft.endDictation() == 16)
    }

    @Test func noSelectionAppends() {
        var draft = draft(body: "Start.")
        draft.beginDictation(at: nil)

        draft.insertFinal("More.")

        #expect(draft.body == "Start. More.")
    }

    @Test func anOutOfRangeOffsetIsClamped() {
        var draft = draft(body: "Hi")
        draft.beginDictation(at: 99)
        draft.insertFinal("there")

        #expect(draft.body == "Hi there")
    }

    @Test func pendingIsDisplayedAtTheInsertionPointAndNeverWrittenToBody() {
        var draft = draft(body: "The brown fox.")
        draft.beginDictation(at: 3)

        draft.handle(.volatile("quick"))

        let display = draft.dictationDisplay
        #expect(display.before == "The")
        #expect(display.pending == " quick")
        #expect(display.after == " brown fox.")
        #expect(draft.body == "The brown fox.")
        #expect(draft.pendingDictation == "quick")
    }

    @Test func aFinalReplacesThePendingText() {
        var draft = draft()
        draft.beginDictation(at: nil)
        draft.handle(.volatile("We turned"))
        draft.handle(.final("We turned back."))

        #expect(draft.body == "We turned back.")
        #expect(draft.pendingDictation.isEmpty)
    }

    @Test func endingDropsPendingText() {
        var draft = draft(body: "Kept.")
        draft.beginDictation(at: nil)
        draft.handle(.final("Final."))
        draft.handle(.volatile("never saved"))

        draft.endDictation()

        #expect(draft.body == "Kept. Final.")
        #expect(draft.dictation == .idle)
        #expect(draft.dictationInsertionPoint == nil)
    }

    @Test func finalsAfterTheEndAreIgnored() {
        var draft = draft(body: "Kept.")
        draft.beginDictation(at: nil)
        draft.endDictation()

        draft.handle(.final("Late."))

        #expect(draft.body == "Kept.")
    }

    @Test func levelsAreClampedAndOnlyApplyWhileListening() {
        var draft = draft()
        draft.handle(.level(0.5))
        #expect(draft.dictation == .idle)

        draft.beginDictation(at: nil)
        draft.handle(.level(3))
        #expect(draft.dictation == .listening(pending: "", elapsedSeconds: 0, level: 1))
        draft.handle(.level(-1))
        #expect(draft.dictation == .listening(pending: "", elapsedSeconds: 0, level: 0))
    }

    @Test func stopKeepsPendingUntilItsFinalArrives() {
        var draft = draft()
        draft.beginDictation(at: nil)
        draft.handle(.volatile("last words"))

        draft.stopDictation()
        #expect(draft.dictation == .finishing(pending: "last words"))

        draft.handle(.final("last words"))
        #expect(draft.body == "last words")
        #expect(draft.dictation == .finishing(pending: ""))
    }

    @Test func dictationStateAloneNeverMakesTheDraftDirty() {
        let original = draft(body: "Same.")
        var draft = original
        draft.dictation = .preparing
        #expect(!draft.isDirty(comparedTo: original))
        draft.dictation = .downloading(progress: 0.5)
        #expect(!draft.isDirty(comparedTo: original))
        draft.beginDictation(at: nil)
        draft.handle(.volatile("pending only"))
        draft.handle(.level(0.7))
        #expect(!draft.isDirty(comparedTo: original))

        draft.handle(.final("Inserted."))
        #expect(draft.isDirty(comparedTo: original))
    }

    @Test func availabilityMapsToTheDictationState() {
        var draft = draft()

        draft.dictationChecked(.available)
        #expect(draft.dictation == .preparing)
        draft.dictationChecked(.needsPermission)
        #expect(draft.dictation == .preparing)
        draft.dictationChecked(.needsModel)
        #expect(draft.dictation == .downloading(progress: 0))
        draft.dictationChecked(.unsupportedLocale)
        #expect(draft.dictation == .unavailable(.unsupportedLanguage))
        draft.dictationChecked(.unsupportedDevice)
        #expect(draft.dictation == .unavailable(.unsupportedDevice))
        draft.dictationChecked(.permissionDenied)
        #expect(draft.dictation == .unavailable(.permissionDenied))
    }

    @Test func downloadProgressIsClampedAndOnlyAppliesWhileDownloading() {
        var draft = draft()
        draft.downloadProgressed(0.5)
        #expect(draft.dictation == .idle)

        draft.dictationChecked(.needsModel)
        draft.downloadProgressed(0.4)
        #expect(draft.dictation == .downloading(progress: 0.4))
        draft.downloadProgressed(1.2)
        #expect(draft.dictation == .downloading(progress: 1))
    }
}

// MARK: Fake service + draft

@MainActor
struct DictationSessionTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// Reads events into the draft until the stream ends, as the composer does.
    private func run(
        _ events: AsyncStream<TranscriptionEvent>, into draft: inout EntryDraft
    ) async {
        for await event in events {
            if case .ended = event {
                break
            }
            draft.handle(event)
        }
    }

    @Test func stopWithPendingTextInsertsTheFinalOnce() async throws {
        let service = FakeTranscriptionService(
            script: [.volatile("The wind"), .volatile("The wind at the saddle")],
            eventDelay: .milliseconds(1)
        )
        var draft = EntryDraft(mode: .newFromList, now: now)
        draft.body = "Up top."
        draft.beginDictation(at: nil)
        let events = try await service.start()

        // Let the script play, then stop as the stop button does.
        try await Task.sleep(for: .milliseconds(100))
        let stopper = Task { await service.stop() }
        draft.stopDictation()
        await run(events, into: &draft)
        await stopper.value
        draft.endDictation()

        #expect(draft.body == "Up top. The wind at the saddle")
    }

    @Test func saveWhileListeningIncludesTheFinalSegment() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let topic = Topic(title: "Sedona trip")
        context.insert(topic)
        let service = FakeTranscriptionService(
            script: [.final("Arrived."), .volatile("It is hot")],
            eventDelay: .milliseconds(1)
        )
        var draft = EntryDraft(mode: .newInTopic(topic), now: now)
        draft.beginDictation(at: nil)
        let events = try await service.start()
        try await Task.sleep(for: .milliseconds(100))

        let stopper = Task { await service.stop() }
        await run(events, into: &draft)
        await stopper.value
        draft.endDictation()
        let entry = draft.makeEntry()

        #expect(entry.body == "Arrived. It is hot")
    }

    @Test func cancelWhileListeningDropsOnlyThePendingTail() async throws {
        let service = FakeTranscriptionService(
            script: [.final("Kept."), .volatile("dropped")],
            eventDelay: .milliseconds(1)
        )
        let original = EntryDraft(mode: .newFromList, now: now)
        var draft = original
        draft.beginDictation(at: nil)
        let events = try await service.start()

        var iterator = events.makeAsyncIterator()
        while let event = await iterator.next() {
            draft.handle(event)
            if draft.pendingDictation == "dropped" {
                break
            }
        }
        draft.endDictation()

        #expect(draft.body == "Kept.")
        // Finals were inserted, so Cancel asks first.
        #expect(draft.isDirty(comparedTo: original))
    }

    @Test func fakeAvailabilityFollowsPermissionAndInstall() async throws {
        let needsPermission = FakeTranscriptionService(availability: .needsPermission)
        #expect(await needsPermission.availability() == .needsPermission)
        #expect(await needsPermission.requestPermission())
        #expect(await needsPermission.availability() == .available)

        let denied = FakeTranscriptionService(
            availability: .needsPermission, grantsPermission: false)
        #expect(await !denied.requestPermission())

        let needsModel = FakeTranscriptionService(
            availability: .needsModel, eventDelay: .milliseconds(1))
        var progress: [Double] = []
        for try await fraction in needsModel.installModel() {
            progress.append(fraction)
        }
        #expect(progress == [0.25, 0.5, 0.75, 1])
        #expect(await needsModel.availability() == .available)
    }

    @Test func aFailedInstallThrows() async {
        let service = FakeTranscriptionService(
            availability: .needsModel, failsInstall: true, eventDelay: .milliseconds(1))
        await #expect(throws: TranscriptionError.downloadFailed) {
            for try await _ in service.installModel() {}
        }
    }
}

// MARK: Level

struct AudioLevelMeterTests {
    @Test func normalizedLevelStaysWithinZeroAndOne() {
        for rms: Float in [-1, 0, 0.000_001, 0.003, 0.1, 0.5, 1, 4, .infinity, .nan] {
            let level = AudioLevelMeter.normalized(rms: rms)
            #expect((0...1).contains(level), "rms \(rms) → \(level)")
        }
        #expect(AudioLevelMeter.normalized(rms: 0) == 0)
        #expect(AudioLevelMeter.normalized(rms: 1) == 1)
        #expect(AudioLevelMeter.normalized(rms: 0.1) > AudioLevelMeter.normalized(rms: 0.01))
    }

    @Test func smoothingRisesGraduallyAndStaysInRange() {
        var meter = AudioLevelMeter()
        let first = meter.update(rms: 1, at: 0)
        #expect(first.map { $0 > 0 && $0 < 1 } == true)

        var time = 0.0
        for _ in 0..<100 {
            time += 0.1
            if let level = meter.update(rms: 10, at: time) {
                #expect((0...1).contains(level))
            }
        }
        #expect(meter.value > 0.99)
    }

    @Test func updatesAreThrottledToAboutTwentyASecond() {
        var meter = AudioLevelMeter()
        #expect(meter.update(rms: 0.5, at: 0) != nil)
        #expect(meter.update(rms: 0.5, at: 0.01) == nil)
        #expect(meter.update(rms: 0.5, at: 0.06) != nil)
    }
}
