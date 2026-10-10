import Foundation
import SwiftData
import Testing

@testable import Commonplace

/// The pure location rules: place names and coordinate text.
struct LocationRuleTests {
    @Test func pointOfInterestUsesItsName() {
        let candidate = PlaceCandidate(
            name: "Bear Rocks Trailhead", isPointOfInterest: true,
            cityWithContext: "Davis, WV", city: "Davis"
        )

        #expect(candidate.placeName == "Bear Rocks Trailhead")
    }

    @Test func nonPointOfInterestUsesLocalityAndRegion() {
        let candidate = PlaceCandidate(
            name: "431 State Route 179", isPointOfInterest: false,
            cityWithContext: "Sedona, AZ", city: "Sedona"
        )

        #expect(candidate.placeName == "Sedona, AZ")
    }

    @Test func fallsBackToLocalityAlone() {
        #expect(PlaceCandidate(name: "Somewhere Rd", city: "Sedona").placeName == "Sedona")
        #expect(PlaceCandidate(cityWithContext: "  ", city: "Sedona").placeName == "Sedona")
    }

    @Test func nothingNameableIsNil() {
        #expect(PlaceCandidate().placeName == nil)
        #expect(PlaceCandidate(name: "Unnamed Road", isPointOfInterest: false).placeName == nil)
        #expect(PlaceCandidate(name: "", isPointOfInterest: true, city: "").placeName == nil)
    }

    @Test func pointOfInterestWithoutANameFallsBackToTheCity() {
        let candidate = PlaceCandidate(
            name: nil, isPointOfInterest: true, cityWithContext: "Sedona, AZ"
        )

        #expect(candidate.placeName == "Sedona, AZ")
    }

    @Test func coordinatesAreFormattedWithHemispheres() {
        #expect(
            LocationLabel.coordinates(latitude: 34.8697, longitude: -111.761)
                == "34.8697° N, 111.7610° W"
        )
        #expect(
            LocationLabel.coordinates(latitude: -33.85678, longitude: 151.21529)
                == "33.8568° S, 151.2153° E"
        )
        #expect(LocationLabel.coordinates(latitude: 0, longitude: 0) == "0.0000° N, 0.0000° E")
    }

    @Test func labelPrefersThePlaceName() {
        #expect(
            LocationLabel.text(placeName: "Airport Mesa", latitude: 34.8553, longitude: -111.78)
                == "Airport Mesa"
        )
        #expect(
            LocationLabel.text(placeName: nil, latitude: 34.8553, longitude: -111.78)
                == "34.8553° N, 111.7800° W"
        )
        #expect(
            LocationLabel.text(placeName: "", latitude: 34.8553, longitude: -111.78)
                == "34.8553° N, 111.7800° W"
        )
    }

    @Test func captureRuleConstants() {
        #expect(LocationCaptureRule.goodAccuracy == 100)
        #expect(LocationCaptureRule.timeout == .seconds(15))
    }

    @Test func fakeServiceReturnsItsFixOrFails() async throws {
        let fix = try await FakeLocationService().currentLocation(timeout: .seconds(15))
        #expect(fix == FakeLocationService.sampleCoordinate)

        await #expect(throws: LocationError.denied) {
            try await FakeLocationService(location: .failure(.denied))
                .currentLocation(timeout: .seconds(15))
        }
        await #expect(throws: LocationError.unavailable) {
            try await FakeLocationService(delay: .seconds(60))
                .currentLocation(timeout: .milliseconds(20))
        }
        await #expect(throws: URLError.self) {
            try await FakeLocationService(failsGeocoding: true).placeName(for: fix)
        }
    }
}

@MainActor
struct LocationDraftTests {
    private let container: ModelContainer
    private let context: ModelContext
    private let located: Topic
    private let plain: Topic
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let fix = Coordinate(latitude: 34.8253, longitude: -111.7885, horizontalAccuracy: 12)

    init() throws {
        container = try ModelContainerFactory.makeInMemory()
        context = ModelContext(container)
        located = Topic(title: "Sedona trip")
        located.capturesLocation = true
        plain = Topic(title: "Cigars")
        context.insert(located)
        context.insert(plain)
        try context.save()
    }

    // MARK: TopicDraft

    @Test func topicDraftCarriesCapturesLocation() throws {
        #expect(TopicDraft(mode: .new).capturesLocation == false)
        #expect(TopicDraft(mode: .edit(located)).capturesLocation)
        #expect(TopicDraft(title: " A ", capturesLocation: true).trimmed.capturesLocation)

        let made = TopicDraft(title: "Trips", capturesLocation: true).makeTopic()
        #expect(made.capturesLocation)
        #expect(TopicDraft(title: "Trips").makeTopic().capturesLocation == false)

        TopicDraft(title: "Cigars", capturesLocation: true).apply(to: plain)
        #expect(plain.capturesLocation)
        TopicDraft(title: "Cigars", capturesLocation: false).apply(to: plain)
        #expect(plain.capturesLocation == false)
    }

    @Test func topicDraftIsDirtyWhenTheToggleChanges() {
        let original = TopicDraft(mode: .edit(located))
        var draft = original
        #expect(!draft.isDirty(comparedTo: original))

        draft.capturesLocation = false
        #expect(draft.isDirty(comparedTo: original))

        draft.capturesLocation = true
        #expect(!draft.isDirty(comparedTo: original))
    }

    // MARK: Initial state

    @Test func newEntryStartsFromTheTopicsSetting() {
        let inLocated = EntryDraft(mode: .newInTopic(located), now: now)
        #expect(inLocated.capturesLocation)
        #expect(inLocated.needsCapture)
        #expect(inLocated.location == .none)

        let inPlain = EntryDraft(mode: .newInTopic(plain), now: now)
        #expect(!inPlain.capturesLocation)
        #expect(!inPlain.needsCapture)
        #expect(inPlain.locationLabel == "No Location")

        let fromList = EntryDraft(mode: .newFromList, now: now)
        #expect(!fromList.capturesLocation)
        #expect(!fromList.needsCapture)
    }

    @Test func editStartsFromWhetherTheEntryHasALocation() throws {
        let with = try savedEntry(
            in: plain, latitude: 34.8553, longitude: -111.78, placeName: "Airport Mesa")
        let without = try savedEntry(in: located)

        let withDraft = EntryDraft(mode: .edit(with), now: now)
        #expect(withDraft.capturesLocation)
        #expect(!withDraft.needsCapture)
        #expect(withDraft.locationLabel == "Airport Mesa")
        #expect(
            withDraft.location
                == .existing(
                    Coordinate(latitude: 34.8553, longitude: -111.78), placeName: "Airport Mesa")
        )

        // The topic's setting doesn't apply to an edit: no location means none is captured.
        let withoutDraft = EntryDraft(mode: .edit(without), now: now)
        #expect(!withoutDraft.capturesLocation)
        #expect(!withoutDraft.needsCapture)
    }

    @Test func existingLocationWithoutANameShowsCoordinates() throws {
        let entry = try savedEntry(in: plain, latitude: 34.8626, longitude: -111.7634)

        #expect(EntryDraft(mode: .edit(entry), now: now).locationLabel == "34.8626° N, 111.7634° W")
    }

    // MARK: Topic changes

    @Test func topicChangeFollowsTheSettingUntilToggledByHand() {
        var draft = EntryDraft(mode: .newFromList, now: now)

        draft.setTopic(located)
        #expect(draft.capturesLocation)
        #expect(draft.needsCapture)

        draft.setTopic(plain)
        #expect(!draft.capturesLocation)
        #expect(draft.location == .none)

        draft.setCapturesLocation(true)
        #expect(draft.hasToggledLocation)
        draft.setTopic(plain)
        #expect(draft.capturesLocation)  // the hand-made choice sticks

        draft.setCapturesLocation(false)
        draft.setTopic(located)
        #expect(!draft.capturesLocation)
        #expect(draft.topic === located)
    }

    @Test func switchingToATopicWithoutLocationDropsACapturedFix() {
        var draft = EntryDraft(mode: .newFromList, now: now)
        draft.setTopic(located)
        draft.captureStarted()
        draft.captureSucceeded(fix)

        draft.setTopic(plain)

        #expect(draft.location == .none)
        #expect(draft.locationLabel == "No Location")
    }

    // MARK: Capture

    @Test func captureMovesThroughLocatingCapturedAndNamed() {
        var draft = EntryDraft(mode: .newInTopic(located), now: now)
        #expect(draft.locationLabel == "Locating…")

        draft.captureStarted()
        #expect(draft.isLocating)
        #expect(!draft.needsCapture)

        draft.captureSucceeded(fix)
        #expect(draft.location == .captured(fix, placeName: nil))
        #expect(draft.locationLabel == "Current Location")

        draft.captureNamed(fix, placeName: "Cathedral Rock Trailhead")
        #expect(draft.locationLabel == "Cathedral Rock Trailhead")
    }

    @Test func aFixThatArrivesAfterTurningLocationOffIsIgnored() {
        var draft = EntryDraft(mode: .newInTopic(located), now: now)
        draft.captureStarted()
        draft.setCapturesLocation(false)

        draft.captureSucceeded(fix)
        draft.captureNamed(fix, placeName: "Cathedral Rock Trailhead")

        #expect(draft.location == .none)
        #expect(!draft.capturesLocation)
    }

    @Test func aNameForADifferentFixIsIgnored() {
        var draft = EntryDraft(mode: .newInTopic(located), now: now)
        draft.captureStarted()
        draft.captureSucceeded(fix)

        draft.captureNamed(Coordinate(latitude: 1, longitude: 2), placeName: "Elsewhere")

        #expect(draft.location == .captured(fix, placeName: nil))
    }

    @Test func failedCaptureShowsDeniedOrUnavailable() {
        var denied = EntryDraft(mode: .newInTopic(located), now: now)
        denied.captureStarted()
        denied.captureFailed(.denied)
        #expect(denied.location == .denied)
        #expect(denied.locationLabel == "Location Off")

        var failed = EntryDraft(mode: .newInTopic(located), now: now)
        failed.captureStarted()
        failed.captureFailed(.unavailable)
        #expect(failed.location == .failed)
        #expect(failed.locationLabel == "Location Unavailable")

        failed.requestCurrentLocation()
        #expect(failed.needsCapture)
    }

    @Test func failedReplacementOnAnEditKeepsTheSavedLocation() throws {
        let entry = try savedEntry(
            in: plain, latitude: 34.8553, longitude: -111.78, placeName: "Airport Mesa")
        var draft = EntryDraft(mode: .edit(entry), now: now)
        let saved = draft.location

        draft.requestCurrentLocation()
        #expect(draft.needsCapture)
        draft.captureStarted()
        draft.captureFailed(.unavailable)

        #expect(draft.location == saved)
        #expect(draft.locationLabel == "Airport Mesa")
    }

    // MARK: Dirty rules

    @Test func automaticCaptureAloneIsNotDirty() {
        let original = EntryDraft(mode: .newInTopic(located), now: now)
        var draft = original
        draft.captureStarted()
        #expect(!draft.isDirty(comparedTo: original))

        draft.captureSucceeded(fix)
        draft.captureNamed(fix, placeName: "Cathedral Rock Trailhead")
        #expect(!draft.isDirty(comparedTo: original))

        var failed = original
        failed.captureStarted()
        failed.captureFailed(.denied)
        #expect(!failed.isDirty(comparedTo: original))
    }

    @Test func togglingLocationIsDirty() {
        let original = EntryDraft(mode: .newInTopic(located), now: now)
        var draft = original
        draft.setCapturesLocation(false)
        #expect(draft.isDirty(comparedTo: original))

        let plainOriginal = EntryDraft(mode: .newInTopic(plain), now: now)
        var plainDraft = plainOriginal
        plainDraft.setCapturesLocation(true)
        #expect(plainDraft.isDirty(comparedTo: plainOriginal))
    }

    @Test func editRemovingOrReplacingALocationIsDirty() throws {
        let entry = try savedEntry(
            in: plain, latitude: 34.8553, longitude: -111.78, placeName: "Airport Mesa")
        let original = EntryDraft(mode: .edit(entry), now: now)
        #expect(!original.isDirty(comparedTo: original))

        var removed = original
        removed.setCapturesLocation(false)
        #expect(removed.isDirty(comparedTo: original))

        var replaced = original
        replaced.requestCurrentLocation()
        replaced.captureStarted()
        #expect(!replaced.isDirty(comparedTo: original))  // nothing to save until the fix arrives
        replaced.captureSucceeded(fix)
        #expect(replaced.isDirty(comparedTo: original))
    }

    @Test func editAddingALocationIsDirty() throws {
        let entry = try savedEntry(in: located)
        let original = EntryDraft(mode: .edit(entry), now: now)
        var draft = original

        draft.setCapturesLocation(true)

        #expect(draft.needsCapture)
        #expect(draft.isDirty(comparedTo: original))
    }

    // MARK: applyLocation

    @Test func capturedLocationSetsAllFields() throws {
        let entry = try savedEntry(in: located)
        var draft = EntryDraft(mode: .edit(entry), now: now)
        draft.setCapturesLocation(true)
        draft.captureStarted()
        draft.captureSucceeded(fix)
        draft.captureNamed(fix, placeName: "Cathedral Rock Trailhead")

        draft.applyLocation(to: entry)

        #expect(entry.latitude == 34.8253)
        #expect(entry.longitude == -111.7885)
        #expect(entry.placeName == "Cathedral Rock Trailhead")
        #expect(entry.hasLocation)
    }

    @Test func capturedWithoutANameSavesCoordinatesOnly() {
        var draft = EntryDraft(mode: .newInTopic(located), now: now)
        draft.captureStarted()
        draft.captureSucceeded(fix)
        let entry = draft.makeEntry()
        context.insert(entry)

        draft.applyLocation(to: entry)

        #expect(entry.hasLocation)
        #expect(entry.placeName == nil)
        #expect(LocationCapture.needsPlaceName(entry))
    }

    @Test func turningLocationOffClearsAllThreeFields() throws {
        let entry = try savedEntry(
            in: plain, latitude: 34.8553, longitude: -111.78, placeName: "Airport Mesa")
        var draft = EntryDraft(mode: .edit(entry), now: now)
        draft.setCapturesLocation(false)

        draft.applyLocation(to: entry)

        #expect(entry.latitude == nil)
        #expect(entry.longitude == nil)
        #expect(entry.placeName == nil)
    }

    @Test func unchangedLocationIsLeftAlone() throws {
        let entry = try savedEntry(
            in: plain, latitude: 34.8553, longitude: -111.78, placeName: "Airport Mesa")
        var draft = EntryDraft(mode: .edit(entry), now: now)
        draft.body = "Edited"
        draft.date = now.addingTimeInterval(-86_400 * 40)  // back-dated

        draft.apply(to: entry)
        draft.applyPhotos(to: entry, in: context)
        draft.applyLocation(to: entry)
        try context.save()

        #expect(entry.latitude == 34.8553)
        #expect(entry.longitude == -111.78)
        #expect(entry.placeName == "Airport Mesa")
    }

    @Test func stillLocatingDeniedOrFailedNeverClearsASavedLocation() throws {
        let entry = try savedEntry(
            in: plain, latitude: 34.8553, longitude: -111.78, placeName: "Airport Mesa")
        var draft = EntryDraft(mode: .edit(entry), now: now)
        draft.requestCurrentLocation()
        draft.captureStarted()

        draft.applyLocation(to: entry)  // saved while still locating

        #expect(entry.latitude == 34.8553)
        #expect(entry.placeName == "Airport Mesa")
    }

    @Test func applyAndApplyPhotosNeverTouchLocation() throws {
        let entry = try savedEntry(
            in: plain, latitude: 34.8553, longitude: -111.78, placeName: "Airport Mesa")
        var draft = EntryDraft(mode: .edit(entry), now: now)
        draft.setCapturesLocation(false)
        draft.body = "Edited"

        draft.apply(to: entry)
        draft.applyPhotos(to: entry, in: context)

        #expect(entry.latitude == 34.8553)
        #expect(entry.longitude == -111.78)
        #expect(entry.placeName == "Airport Mesa")
    }

    private func savedEntry(
        in topic: Topic, latitude: Double? = nil, longitude: Double? = nil, placeName: String? = nil
    ) throws -> Entry {
        let entry = Entry(body: "Entry text", date: now.addingTimeInterval(-3_600), topic: topic)
        entry.latitude = latitude
        entry.longitude = longitude
        entry.placeName = placeName
        context.insert(entry)
        try context.save()
        return entry
    }
}

@MainActor
struct LocationCaptureTests {
    private let container: ModelContainer
    private let context: ModelContext
    private let topic: Topic
    private let fix = FakeLocationService.sampleCoordinate

    init() throws {
        container = try ModelContainerFactory.makeInMemory()
        context = container.mainContext
        topic = Topic(title: "Sedona trip")
        context.insert(topic)
        try context.save()
    }

    // MARK: Late fix

    @Test func lateFixAttachesToTheSavedEntryAndNamesIt() async throws {
        let entry = try savedEntry()
        let capture = LocationCapture(
            service: FakeLocationService(delay: .milliseconds(20)), context: context)

        await capture.attachWhenLocated(to: entry.persistentModelID, timeout: .seconds(5))

        #expect(entry.latitude == fix.latitude)
        #expect(entry.longitude == fix.longitude)
        #expect(entry.placeName == "Cathedral Rock Trailhead")
        #expect(!context.hasChanges)
    }

    @Test func lateFixOfflineSavesCoordinatesWithoutAName() async throws {
        let entry = try savedEntry()
        let capture = LocationCapture(
            service: FakeLocationService(failsGeocoding: true), context: context)

        await capture.attachWhenLocated(to: entry.persistentModelID, timeout: .seconds(5))

        #expect(entry.hasLocation)
        #expect(entry.placeName == nil)
    }

    @Test func lateFixDoesNotOverwriteAnExistingLocation() async throws {
        let entry = try savedEntry(
            latitude: 39.0637, longitude: -79.3035, placeName: "Bear Rocks Trailhead")
        let capture = LocationCapture(service: FakeLocationService(), context: context)

        await capture.attachWhenLocated(to: entry.persistentModelID, timeout: .seconds(5))

        #expect(entry.latitude == 39.0637)
        #expect(entry.longitude == -79.3035)
        #expect(entry.placeName == "Bear Rocks Trailhead")
        #expect(!capture.attach(fix, to: entry.persistentModelID))
    }

    @Test func lateFixDoesNotWriteToATrashedEntry() async throws {
        let entry = try savedEntry()
        entry.deletedAt = .now
        try context.save()
        let capture = LocationCapture(service: FakeLocationService(), context: context)

        await capture.attachWhenLocated(to: entry.persistentModelID, timeout: .seconds(5))

        #expect(!entry.hasLocation)
        #expect(entry.placeName == nil)
    }

    @Test func lateFixGivesUpAfterTheWindow() async throws {
        let entry = try savedEntry()
        let capture = LocationCapture(
            service: FakeLocationService(delay: .seconds(60)), context: context)

        await capture.attachWhenLocated(to: entry.persistentModelID, timeout: .milliseconds(30))

        #expect(!entry.hasLocation)
    }

    @Test func lateFixWithDeniedAccessLeavesNoLocation() async throws {
        let entry = try savedEntry()
        let capture = LocationCapture(
            service: FakeLocationService(location: .failure(.denied)), context: context)

        await capture.attachWhenLocated(to: entry.persistentModelID, timeout: .seconds(5))

        #expect(!entry.hasLocation)
    }

    // MARK: Backfill

    @Test func onlyLiveEntriesWithCoordinatesAndNoNameNeedAPlaceName() throws {
        let needs = try savedEntry(latitude: 34.86, longitude: -111.76)
        let named = try savedEntry(latitude: 34.86, longitude: -111.76, placeName: "Sedona, AZ")
        let noLocation = try savedEntry()
        let trashed = try savedEntry(latitude: 34.86, longitude: -111.76)
        trashed.deletedAt = .now
        let halfSet = try savedEntry()
        halfSet.latitude = 34.86
        let trashedTopic = Topic(title: "Kitchen remodel")
        trashedTopic.deletedAt = .now
        context.insert(trashedTopic)
        let inTrashedTopic = try savedEntry(
            latitude: 34.86, longitude: -111.76, topic: trashedTopic)
        try context.save()

        #expect(LocationCapture.needsPlaceName(needs))
        #expect(!LocationCapture.needsPlaceName(named))
        #expect(!LocationCapture.needsPlaceName(noLocation))
        #expect(!LocationCapture.needsPlaceName(trashed))
        #expect(!LocationCapture.needsPlaceName(halfSet))
        #expect(!LocationCapture.needsPlaceName(inTrashedTopic))

        let fetched = try context.fetch(LocationCapture.needsPlaceNameDescriptor)
        #expect(
            fetched.filter(LocationCapture.needsPlaceName).map(\.persistentModelID) == [
                needs.persistentModelID
            ])
        #expect(!fetched.contains { $0 === named || $0 === noLocation })
    }

    @Test func backfillNamesEntriesSavedWithoutOne() async throws {
        let first = try savedEntry(latitude: 34.86, longitude: -111.76)
        let second = try savedEntry(latitude: 39.06, longitude: -79.30)
        let named = try savedEntry(latitude: 34.86, longitude: -111.76, placeName: "Sedona, AZ")
        let capture = LocationCapture(
            service: FakeLocationService(placeName: "Airport Mesa"), context: context)

        await capture.backfillPlaceNames()

        #expect(first.placeName == "Airport Mesa")
        #expect(second.placeName == "Airport Mesa")
        #expect(named.placeName == "Sedona, AZ")
        #expect(!context.hasChanges)
    }

    @Test func backfillNamesAFewAtATime() async throws {
        for _ in 0..<(LocationCapture.backfillBatchSize + 3) {
            _ = try savedEntry(latitude: 34.86, longitude: -111.76)
        }
        let capture = LocationCapture(service: FakeLocationService(), context: context)

        await capture.backfillPlaceNames()
        #expect(try namedCount() == LocationCapture.backfillBatchSize)

        await capture.backfillPlaceNames()
        #expect(try namedCount() == LocationCapture.backfillBatchSize + 3)
    }

    @Test func backfillOfflineChangesNothing() async throws {
        let entry = try savedEntry(latitude: 34.86, longitude: -111.76)
        let capture = LocationCapture(
            service: FakeLocationService(failsGeocoding: true), context: context)

        await capture.backfillPlaceNames()

        #expect(entry.placeName == nil)
        #expect(entry.hasLocation)
    }

    @Test func backfillLeavesUnnameablePlacesAsCoordinates() async throws {
        let entry = try savedEntry(latitude: 0, longitude: -140)
        let capture = LocationCapture(
            service: FakeLocationService(placeName: nil), context: context)

        await capture.backfillPlaceNames()
        await capture.backfillPlaceNames()

        #expect(entry.placeName == nil)
        #expect(entry.hasLocation)
    }

    // MARK: Helpers

    private func savedEntry(
        latitude: Double? = nil, longitude: Double? = nil, placeName: String? = nil,
        topic: Topic? = nil
    ) throws -> Entry {
        let entry = Entry(body: "Entry text", topic: topic ?? self.topic)
        entry.latitude = latitude
        entry.longitude = longitude
        entry.placeName = placeName
        context.insert(entry)
        try context.save()
        return entry
    }

    private func namedCount() throws -> Int {
        try context.fetch(FetchDescriptor<Entry>()).filter { $0.placeName != nil }.count
    }
}
