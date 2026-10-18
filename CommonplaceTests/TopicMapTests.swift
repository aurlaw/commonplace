import CoreLocation
import Foundation
import MapKit
import SwiftData
import Testing

@testable import Commonplace

@MainActor
struct TopicMapEntriesTests {
    private let container: ModelContainer
    private let context: ModelContext
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let topic: Topic

    init() throws {
        container = try ModelContainerFactory.makeInMemory()
        context = ModelContext(container)
        topic = Topic(title: "Sedona trip")
        context.insert(topic)
        try context.save()
    }

    @Test func locatedEntriesAreLiveWithBothCoordinatesNewestFirst() throws {
        let older = entry("Older", daysAgo: 3, latitude: 34.86, longitude: -111.76)
        let newer = entry("Newer", daysAgo: 1, latitude: 34.82, longitude: -111.79)
        _ = entry("Latitude only", daysAgo: 0, latitude: 34.8, longitude: nil)
        _ = entry("Longitude only", daysAgo: 0, latitude: nil, longitude: -111.8)
        _ = entry("No location", daysAgo: 0, latitude: nil, longitude: nil)
        let trashed = entry("Trashed", daysAgo: 0, latitude: 34.9, longitude: -111.7)
        trashed.deletedAt = now
        try context.save()

        #expect(TopicMapModel.locatedEntries(for: topic).map(\.body) == ["Newer", "Older"])
        #expect(TopicMapModel.locatedEntries(for: topic).first === newer)
        #expect(TopicMapModel.locatedEntries(for: topic).last === older)
        // Every live entry counts toward "of M", located or not; the trashed one doesn't.
        #expect(TopicMapModel.liveEntryCount(for: topic) == 5)
    }

    @Test func sameDateEntriesAreOrderedByCreation() throws {
        let first = entry("First", daysAgo: 1, latitude: 34.86, longitude: -111.76)
        let second = entry("Second", daysAgo: 1, latitude: 34.86, longitude: -111.76)
        second.createdAt = first.createdAt.addingTimeInterval(60)
        try context.save()

        #expect(TopicMapModel.locatedEntries(for: topic).map(\.body) == ["Second", "First"])
    }

    @Test func aTrashedTopicHasNoLocatedEntries() throws {
        _ = entry("Located", daysAgo: 1, latitude: 34.86, longitude: -111.76)
        topic.deletedAt = now
        try context.save()

        #expect(TopicMapModel.locatedEntries(for: topic).isEmpty)
        #expect(TopicMapModel.liveEntryCount(for: topic) == 0)
    }

    @Test func movingAnEntryAwayTakesItOffTheMap() throws {
        let moving = entry("Moving", daysAgo: 1, latitude: 34.86, longitude: -111.76)
        let other = Topic(title: "Dolly Sods")
        context.insert(other)
        try context.save()
        #expect(TopicMapModel.locatedEntries(for: topic).count == 1)

        #expect(EntryOperations(context: context).move(moving, to: other) == nil)

        #expect(TopicMapModel.locatedEntries(for: topic).isEmpty)
        #expect(TopicMapModel.locatedEntries(for: other).map(\.body) == ["Moving"])
    }

    private func entry(
        _ body: String, daysAgo: Int, latitude: Double?, longitude: Double?
    ) -> Entry {
        let date = now.addingTimeInterval(-Double(daysAgo) * 86_400)
        let entry = Entry(body: body, date: date, topic: topic, createdAt: date)
        entry.latitude = latitude
        entry.longitude = longitude
        context.insert(entry)
        return entry
    }
}

struct TopicMapModelTests {
    private let sedona = CLLocationCoordinate2D(latitude: 34.8697, longitude: -111.7610)

    // MARK: Caption and labels

    @Test func captionCountsLocatedOfAll() {
        #expect(
            TopicMapModel.caption(located: 12, total: 23) == "12 of 23 entries have a location")
        #expect(TopicMapModel.caption(located: 1, total: 5) == "1 of 5 entries has a location")
        #expect(TopicMapModel.caption(located: 1, total: 1) == "1 of 1 entry has a location")
        #expect(TopicMapModel.caption(located: 0, total: 3) == "0 of 3 entries have a location")
    }

    @Test func groupLabelNamesThePlace() {
        #expect(
            TopicMapModel.groupLabel(count: 5, near: "Cathedral Rock")
                == "5 entries near Cathedral Rock, zoom in")
    }

    @Test func firstLineIsTheFirstNonBlankPlainLine() {
        #expect(TopicMapModel.firstLine(of: "\n  **Bold** start  \nSecond") == "Bold start")
        #expect(
            TopicMapModel.firstLine(of: "- [Trail](https://example.com) notes") == "Trail notes")
        #expect(TopicMapModel.firstLine(of: " \n\n ") == nil)
        #expect(TopicMapModel.firstLine(of: "") == nil)
    }

    @Test func mapStyleFallsBackToStandard() {
        #expect(TopicMapStyle(storedValue: "satellite") == .satellite)
        #expect(TopicMapStyle(storedValue: "hybrid") == .hybrid)
        #expect(TopicMapStyle(storedValue: "terrain") == .standard)
        #expect(TopicMapStyle(storedValue: "") == .standard)
    }

    // MARK: Fitting

    @Test func noPointsHaveNoRegion() {
        #expect(TopicMapModel.fittingRegion(for: []) == nil)
    }

    @Test func onePointGetsTheMinimumSpan() throws {
        let region = try #require(TopicMapModel.fittingRegion(for: [sedona]))
        #expect(region.center.latitude == sedona.latitude)
        #expect(region.center.longitude == sedona.longitude)
        // About 1 km each way.
        #expect(abs(region.span.latitudeDelta * 111_320 - 1_000) < 1)
        #expect(abs(TopicMapModel.widthMeters(of: region) - 1_000) < 1)
    }

    @Test func severalPointsAreCenteredWithPadding() throws {
        let points = [
            CLLocationCoordinate2D(latitude: 34.80, longitude: -111.80),
            CLLocationCoordinate2D(latitude: 34.90, longitude: -111.75),
            CLLocationCoordinate2D(latitude: 34.85, longitude: -111.70),
        ]
        let region = try #require(TopicMapModel.fittingRegion(for: points))
        #expect(abs(region.center.latitude - 34.85) < 1e-9)
        #expect(abs(region.center.longitude - -111.75) < 1e-9)
        #expect(abs(region.span.latitudeDelta - 0.10 * TopicMapModel.padding) < 1e-9)
        #expect(abs(region.span.longitudeDelta - 0.10 * TopicMapModel.padding) < 1e-9)
    }

    @Test func farApartPointsAreAllInside() throws {
        let pittsburgh = CLLocationCoordinate2D(latitude: 40.4406, longitude: -79.9959)
        let region = try #require(TopicMapModel.fittingRegion(for: [sedona, pittsburgh]))
        for point in [sedona, pittsburgh] {
            #expect(abs(point.latitude - region.center.latitude) < region.span.latitudeDelta / 2)
            #expect(
                abs(point.longitude - region.center.longitude) < region.span.longitudeDelta / 2)
        }
        #expect(region.span.longitudeDelta < 360)
    }

    @Test func closePointsStillGetTheMinimumSpan() throws {
        let nearby = CLLocationCoordinate2D(
            latitude: sedona.latitude + 0.0001, longitude: sedona.longitude)
        let region = try #require(TopicMapModel.fittingRegion(for: [sedona, nearby]))
        #expect(TopicMapModel.widthMeters(of: region) >= 999)
    }

    // MARK: Grouping

    /// On a 400-point-wide map 10 km across, 44 points is 1.1 km.
    @Test func closePointsMerge() {
        let pins = [pin("a", north: 0), pin("b", north: 10), pin("c", east: 20)]
        let groups = TopicMapModel.groups(pins, region: region(widthMeters: 10_000), mapWidth: 400)
        #expect(groups.map(\.members) == [["a", "b", "c"]])
        #expect(groups.first?.count == 3)
        #expect(groups.first?.isSingle == false)
    }

    @Test func distantPointsStaySeparate() {
        let pins = [pin("a", north: 0), pin("b", north: 5_000), pin("c", east: -5_000)]
        let groups = TopicMapModel.groups(pins, region: region(widthMeters: 10_000), mapWidth: 400)
        #expect(groups.map(\.members) == [["a"], ["b"], ["c"]])
        #expect(groups.allSatisfy { $0.isSingle })
    }

    @Test func zoomingInSplitsAGroup() {
        let pins = [pin("a", north: 0), pin("b", north: 200)]
        let far = TopicMapModel.groups(pins, region: region(widthMeters: 10_000), mapWidth: 400)
        #expect(far.map(\.members) == [["a", "b"]])
        // 1 km across: 44 points is 110 m, so 200 m apart is two pins.
        let near = TopicMapModel.groups(pins, region: region(widthMeters: 1_000), mapWidth: 400)
        #expect(near.map(\.members) == [["a"], ["b"]])
    }

    @Test func atTheClosestZoomEvenTheSameSpotComesApart() {
        let pins = [pin("a", north: 0), pin("b", north: 0)]
        let groups = TopicMapModel.groups(
            pins, region: region(widthMeters: TopicMapModel.ungroupedWidthMeters - 50),
            mapWidth: 400)
        #expect(groups.map(\.members) == [["a"], ["b"]])
        // Zooming to a bubble fits it narrower than that, so the tap always splits it.
        #expect(TopicMapModel.groupZoomSpanMeters < TopicMapModel.ungroupedWidthMeters)
    }

    @Test func groupCentroidIsTheMeanOfItsMembers() throws {
        let pins = [pin("a", north: 0), pin("b", north: 30), pin("c", east: 60)]
        let group = try #require(
            TopicMapModel.groups(pins, region: region(widthMeters: 10_000), mapWidth: 400).first)
        let latitude = pins.map(\.latitude).reduce(0, +) / 3
        let longitude = pins.map(\.longitude).reduce(0, +) / 3
        #expect(abs(group.latitude - latitude) < 1e-12)
        #expect(abs(group.longitude - longitude) < 1e-12)
    }

    @Test func groupingDoesNotDependOnPanning() {
        let pins = [pin("a", north: 0), pin("b", north: 300), pin("c", north: 3_000)]
        let here = region(widthMeters: 5_000)
        var panned = here
        panned.center.latitude += 0.02
        panned.center.longitude -= 0.03
        #expect(
            TopicMapModel.groups(pins, region: here, mapWidth: 400).map(\.members)
                == TopicMapModel.groups(pins, region: panned, mapWidth: 400).map(\.members))
    }

    @Test func noMapSizeMeansNoGrouping() {
        let pins = [pin("a", north: 0), pin("b", north: 1)]
        #expect(
            TopicMapModel.groups(pins, region: region(widthMeters: 10_000), mapWidth: 0)
                .map(\.members) == [["a"], ["b"]])
    }

    /// A pin offset from Sedona by meters.
    private func pin(_ id: String, north: Double = 0, east: Double = 0) -> MapPin<String> {
        MapPin(
            id: id,
            latitude: sedona.latitude + north / 111_320,
            longitude: sedona.longitude
                + east / (111_320 * cos(sedona.latitude * .pi / 180))
        )
    }

    private func region(widthMeters: Double) -> MKCoordinateRegion {
        let longitudeDelta = widthMeters / (111_320 * cos(sedona.latitude * .pi / 180))
        return MKCoordinateRegion(
            center: sedona,
            span: MKCoordinateSpan(latitudeDelta: longitudeDelta, longitudeDelta: longitudeDelta)
        )
    }
}
