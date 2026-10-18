import Foundation
import SwiftData
import Testing

@testable import Commonplace

// MARK: - Parser

struct GPXParserTests {
    @Test func readsTwoSegmentsWithACDATANameAndMixedTimes() throws {
        let gpx = """
            <?xml version="1.0"?>
            <gpx xmlns="http://www.topografix.com/GPX/1/1" version="1.1" creator="Test">
              <metadata><name>Metadata name</name></metadata>
              <wpt lat="1" lon="1"><name>Ignored waypoint</name></wpt>
              <trk>
                <name><![CDATA[Afternoon hike at Broken Arrow Trail]]></name>
                <extensions><color>red</color></extensions>
                <trkseg>
                  <trkpt lat="34.84555" lon="-111.75681">
                    <ele>1305.29</ele><time>2026-10-14T19:45:08Z</time>
                  </trkpt>
                  <trkpt lat="34.84554" lon="-111.75685">
                    <time>2026-10-14T19:45:22.500Z</time>
                  </trkpt>
                </trkseg>
                <trkseg>
                  <trkpt lat="34.8456" lon="-111.757"><ele>1310</ele></trkpt>
                </trkseg>
              </trk>
            </gpx>
            """
        let track = try GPXParser.parse(Data(gpx.utf8))

        #expect(track.name == "Afternoon hike at Broken Arrow Trail")
        #expect(track.segments.map(\.count) == [2, 1])
        let first = track.segments[0][0]
        #expect(first.latitude == 34.84555)
        #expect(first.longitude == -111.75681)
        #expect(first.elevation == 1305.29)
        #expect(first.time == Date(timeIntervalSince1970: 1_792_007_108))
        let second = track.segments[0][1]
        #expect(second.elevation == nil)
        #expect(second.time == Date(timeIntervalSince1970: 1_792_007_122.5))
        #expect(track.segments[1][0].elevation == 1310)
        #expect(track.segments[1][0].time == nil)
    }

    @Test func fallsBackToRoutePoints() throws {
        let gpx = """
            <gpx xmlns="http://www.topografix.com/GPX/1/1" version="1.1">
              <rte><name>Planned loop</name>
                <rtept lat="34.0" lon="-111.0"><ele>1000</ele></rtept>
                <rtept lat="34.1" lon="-111.1"><ele>1010</ele></rtept>
                <rtept lat="34.2" lon="-111.2"/>
              </rte>
            </gpx>
            """
        let track = try GPXParser.parse(Data(gpx.utf8))
        #expect(track.name == "Planned loop")
        #expect(track.segments.map(\.count) == [3])
    }

    @Test func prefixedElementsAreRead() throws {
        let gpx = """
            <g:gpx xmlns:g="http://www.topografix.com/GPX/1/1" version="1.1">
              <g:trk><g:trkseg>
                <g:trkpt lat="34.0" lon="-111.0"/><g:trkpt lat="34.1" lon="-111.1"/>
              </g:trkseg></g:trk>
            </g:gpx>
            """
        #expect(try GPXParser.parse(Data(gpx.utf8)).pointCount == 2)
    }

    @Test func otherXMLIsNotGPX() {
        let xml = #"<?xml version="1.0"?><kml><Placemark/></kml>"#
        #expect(throws: GPXError.notGPX) { try GPXParser.parse(Data(xml.utf8)) }
    }

    @Test func garbageIsNotGPX() {
        #expect(throws: GPXError.notGPX) { try GPXParser.parse(Data([0xFF, 0x00, 0x13, 0x37])) }
        #expect(throws: GPXError.notGPX) { try GPXParser.parse(Data("not xml at all".utf8)) }
    }

    @Test func fewerThanTwoPointsIsNoTrack() {
        let one = """
            <gpx version="1.1"><trk><trkseg><trkpt lat="34" lon="-111"/></trkseg></trk>
            <wpt lat="34" lon="-111"/></gpx>
            """
        #expect(throws: GPXError.noTrack) { try GPXParser.parse(Data(one.utf8)) }
        #expect(throws: GPXError.noTrack) { try GPXParser.parse(Data("<gpx/>".utf8)) }
    }

    @Test func tooManyPointsIsRejected() {
        let points = String(
            repeating: #"<trkpt lat="34" lon="-111"/>"#, count: RouteLimits.maxPoints + 1)
        let gpx = "<gpx><trk><trkseg>\(points)</trkseg></trk></gpx>"
        #expect(throws: GPXError.tooManyPoints) { try GPXParser.parse(Data(gpx.utf8)) }
    }

    @Test func exactlyTheMaximumIsAccepted() throws {
        let points = String(
            repeating: #"<trkpt lat="34" lon="-111"/>"#, count: RouteLimits.maxPoints)
        let gpx = "<gpx><trk><trkseg>\(points)</trkseg></trk></gpx>"
        #expect(try GPXParser.parse(Data(gpx.utf8)).pointCount == RouteLimits.maxPoints)
    }

    @Test func oversizedFilesAreRejectedBeforeParsing() {
        let data = Data(repeating: 0x20, count: RouteLimits.maxFileBytes + 1)
        #expect(throws: GPXError.tooLarge) { try GPXParser.parse(data) }
    }

    @Test func errorsHaveUserFacingMessages() {
        #expect(GPXError.noTrack.message == "This file doesn’t contain a track.")
        #expect(GPXError.notGPX.message == "This file isn’t a GPX file.")
    }

    @Test func nameFallsBackToTheFileName() {
        #expect(RouteDraft.name(track: nil, fileName: "Broken Arrow.gpx") == "Broken Arrow")
        #expect(RouteDraft.name(track: "  ", fileName: "loop.GPX") == "loop")
        #expect(RouteDraft.name(track: "Named", fileName: "file.gpx") == "Named")
        #expect(RouteDraft.name(track: nil, fileName: "") == "Route")
    }
}

// MARK: - Metrics

struct RouteMetricsTests {
    @Test func haversineOnKnownPairs() {
        // One degree of latitude on a 6,371 km sphere.
        let degree = RouteMetrics.haversine((0, 0), (1, 0))
        #expect(abs(degree - 111_194.93) < 0.1)
        // Pittsburgh to Sedona, about 2,768 km.
        let far = RouteMetrics.haversine((40.4406, -79.9959), (34.8697, -111.7610))
        #expect(abs(far - 2_920_000) < 200_000)
        #expect(RouteMetrics.haversine((34.8, -111.7), (34.8, -111.7)) == 0)
    }

    @Test func distanceIsNotCountedAcrossSegmentGaps() {
        let a = [point(0, 0), point(0.001, 0)]
        let b = [point(1, 1), point(1.001, 1)]
        let within = RouteMetrics.distance(segments: [a])
        #expect(abs(RouteMetrics.distance(segments: [a, b]) - 2 * within) < 1e-6)
        #expect(RouteMetrics.distance(segments: [a + b]) > 100_000)
    }

    @Test func noiseUnderTheThresholdGainsNothing() {
        let segments = [elevations([100, 104, 99, 103.9, 100, 96.5, 100])]
        #expect(RouteMetrics.elevationGain(segments: segments) == 0)
    }

    @Test func aSteadyClimbGainsItsRise() {
        let segments = [elevations([100, 102, 104, 106, 108, 110, 112])]
        // 100→106 (+6, ref 106), 106→112 (+6).
        #expect(RouteMetrics.elevationGain(segments: segments) == 12)
    }

    @Test func climbDipClimbCountsBothClimbs() {
        let segments = [elevations([100, 120, 110, 130])]
        // +20 (ref 120); −10 (ref 110); +20.
        #expect(RouteMetrics.elevationGain(segments: segments) == 40)
    }

    @Test func pointsWithoutElevationAreSkipped() {
        let segments = [
            [point(0, 0, ele: 100), point(0, 0), point(0, 0, ele: 110)],
            [point(0, 0), point(0, 0, ele: 120)],
        ]
        #expect(RouteMetrics.elevationGain(segments: segments) == 20)
        #expect(RouteMetrics.minElevation(segments: segments) == 100)
        #expect(RouteMetrics.maxElevation(segments: segments) == 120)
    }

    @Test func noElevationsMeansNoGain() {
        let segments = [[point(0, 0), point(0.01, 0)]]
        #expect(RouteMetrics.elevationGain(segments: segments) == nil)
        #expect(RouteMetrics.minElevation(segments: segments) == nil)
        #expect(RouteMetrics.maxElevation(segments: segments) == nil)
        #expect(RouteMetrics.profile(segments: segments) == nil)
    }

    @Test func startAndEndTimesAndStartCoordinate() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 6_760)
        let segments = [
            [point(34.1, -111.1), point(34.2, -111.2, time: start)],
            [point(34.3, -111.3, time: end), point(34.4, -111.4)],
        ]
        #expect(RouteMetrics.startTime(segments: segments) == start)
        #expect(RouteMetrics.endTime(segments: segments) == end)
        #expect(
            RouteMetrics.startCoordinate(segments: segments)
                == Coordinate(latitude: 34.1, longitude: -111.1))
        #expect(RouteMetrics.startTime(segments: [[point(0, 0)]]) == nil)
    }

    // MARK: Simplification

    @Test func aStraightLineCollapsesToItsEndpoints() {
        let line = (0...100).map { point(34 + Double($0) * 0.0001, -111) }
        let path = RouteMetrics.simplifiedPath(segments: [line])
        #expect(path.segments == [[[34, -111], [line[100].latitude, -111]]])
    }

    @Test func aZigzagKeepsItsCorners() {
        // Corners about 55 m apart, well over the 5 m tolerance; midpoints on each leg go.
        var zigzag: [TrackPoint] = []
        for corner in 0..<6 {
            let longitude = corner.isMultiple(of: 2) ? -111.0 : -110.9994
            zigzag.append(point(34 + Double(corner) * 0.0005, longitude))
            if corner < 5 {
                let nextLongitude = corner.isMultiple(of: 2) ? -110.9994 : -111.0
                zigzag.append(
                    point(34 + (Double(corner) + 0.5) * 0.0005, (longitude + nextLongitude) / 2))
            }
        }
        let path = RouteMetrics.simplifiedPath(segments: [zigzag])
        #expect(path.pointCount == 6)
        #expect(path.segments[0].first == [zigzag[0].latitude, zigzag[0].longitude])
        #expect(path.segments[0].last == [zigzag.last!.latitude, zigzag.last!.longitude])
    }

    @Test func aLongTrackIsCappedAndKeepsItsSegments() {
        // 50,000 points of a jittery circle in two segments.
        let count = RouteLimits.maxPoints
        let points = (0..<count).map { index -> TrackPoint in
            let angle = Double(index) / Double(count) * 2 * .pi * 25
            let jitter = index.isMultiple(of: 2) ? 0.0002 : -0.0002
            return point(34 + 0.05 * sin(angle) + jitter, -111 + 0.05 * cos(angle))
        }
        let segments = [Array(points[..<30_000]), Array(points[30_000...])]
        let path = RouteMetrics.simplifiedPath(segments: segments)
        #expect(path.pointCount <= RouteLimits.maxPathPoints)
        #expect(path.segments.count == 2)
        #expect(path.segments.allSatisfy { $0.count >= 2 })
        #expect(path.segments[1].first == [points[30_000].latitude, points[30_000].longitude])
    }

    @Test func singlePointSegmentsSurvive() {
        let segments = [[point(1, 1)], [point(2, 2), point(3, 3)]]
        let path = RouteMetrics.simplifiedPath(segments: segments)
        #expect(path.segments.map(\.count) == [1, 2])
    }

    // MARK: Profile

    @Test func profileIsEvenlySpacedFromStartToEnd() throws {
        let climb = (0...50).map {
            point(34 + Double($0) * 0.001, -111, ele: 1_000 + Double($0) * 2)
        }
        let profile = try #require(RouteMetrics.profile(segments: [climb]))
        let points = profile.points
        #expect(points.count == RouteLimits.profileSamples)
        #expect(points.first?.distance == 0)
        #expect(points.first?.elevation == 1_000)
        #expect(abs((points.last?.distance ?? 0) - RouteMetrics.distance(segments: [climb])) < 1e-6)
        #expect(points.last?.elevation == 1_100)
        #expect(zip(points, points.dropFirst()).allSatisfy { $0.distance < $1.distance })
    }

    @Test func profileInterpolatesBetweenElevations() throws {
        let segments = [[point(0, 0, ele: 100), point(0, 0.001), point(0, 0.002, ele: 200)]]
        let profile = try #require(RouteMetrics.profile(segments: segments, samples: 3))
        #expect(profile.points.map(\.elevation) == [100, 150, 200])
    }

    // MARK: Encoding

    @Test func pathAndProfileRoundTrip() throws {
        let path = RoutePath(segments: [[[34.1, -111.1], [34.2, -111.2]], [[34.3, -111.3]]])
        #expect(try RoutePath.decode(path.encoded()) == path)
        #expect(
            try RoutePath.decode(path.encoded()).coordinates.map { $0.map(\.latitude) }
                == [[34.1, 34.2], [34.3]])
        let profile = RouteProfile(samples: [[0, 1300], [120.5, 1310.25]])
        #expect(try RouteProfile.decode(profile.encoded()) == profile)
    }

    @Test func draftCarriesEveryField() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let track = ParsedTrack(
            name: "Loop",
            segments: [
                [
                    point(34.8, -111.7, ele: 1_300, time: start),
                    point(34.801, -111.7, ele: 1_310, time: start.addingTimeInterval(600)),
                ]
            ])
        let draft = try RouteDraft(track: track, gpxData: Data([1]), fileName: "x.gpx")
        #expect(draft.name == "Loop")
        #expect(draft.startedAt == start)
        #expect(draft.endedAt == start.addingTimeInterval(600))
        #expect(draft.elevationGainMeters == 10)
        #expect(draft.minElevationMeters == 1_300)
        #expect(draft.maxElevationMeters == 1_310)
        #expect(draft.startCoordinate == Coordinate(latitude: 34.8, longitude: -111.7))
        #expect(try RoutePath.decode(draft.pathData).pointCount == 2)
        #expect(draft.profileData != nil)

        let route = draft.makeRoute()
        #expect(route.name == "Loop")
        #expect(route.gpxData == Data([1]))
        #expect(route.distanceMeters == draft.distanceMeters)
        #expect(route.pathData == draft.pathData)
        #expect(route.startCoordinate == draft.startCoordinate)
    }

    // MARK: Helpers

    private func point(
        _ latitude: Double, _ longitude: Double, ele: Double? = nil, time: Date? = nil
    ) -> TrackPoint {
        TrackPoint(latitude: latitude, longitude: longitude, elevation: ele, time: time)
    }

    private func elevations(_ values: [Double]) -> [TrackPoint] {
        values.map { point(0, 0, ele: $0) }
    }
}

// MARK: - Stats text

struct RouteStatsTests {
    private let us = Locale(identifier: "en_US")
    private let germany = Locale(identifier: "de_DE")
    private let stats = RouteStats(
        distanceMeters: 4_828.03, elevationGainMeters: 121,
        startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 5_760))

    @Test func usUnits() {
        #expect(stats.distance(locale: us) == "3.0 mi")
        #expect(stats.elevationGain(locale: us) == "397 ft")
        #expect(stats.time(locale: us) == "1h 36m")
        #expect(stats.spokenSummary(locale: us) == "3.0 miles, 397 feet gain, 1 hour, 36 minutes")
    }

    @Test func metricUnits() {
        #expect(stats.distance(locale: germany) == "4,8 km")
        #expect(stats.elevationGain(locale: germany) == "121 m")
    }

    @Test func missingGainAndTimeAreLeftOut() {
        let bare = RouteStats(distanceMeters: 1_609.344)
        #expect(bare.elevationGain(locale: us) == nil)
        #expect(bare.time(locale: us) == nil)
        #expect(bare.spokenSummary(locale: us) == "1.0 miles")
    }

    @Test func elevationRangeIsSpoken() {
        #expect(
            RouteStats.elevationRange(min: 1_305.15, max: 1_411.53, locale: us)
                == "Elevation from 4,282 to 4,631 feet")
    }
}

// MARK: - Confirm sheet text

struct RouteAttachTextTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = TimeZone(identifier: "America/Phoenix")!
        return calendar
    }()

    @Test func aDifferentDayGetsAQuietNote() {
        let recorded = date(2026, 10, 14, 12, 45)
        #expect(
            RouteAttachText.dateNote(
                recorded: recorded, entryDate: date(2026, 10, 15, 8, 0), calendar: calendar)
                == "Recorded Oct 14 · entry dated Oct 15")
        #expect(
            RouteAttachText.dateNote(
                recorded: recorded, entryDate: date(2026, 10, 14, 21, 0), calendar: calendar)
                == nil)
        #expect(
            RouteAttachText.dateNote(
                recorded: nil, entryDate: date(2026, 10, 14, 21, 0), calendar: calendar) == nil)
    }

    @Test func summaryReadsNameDateAndStats() {
        let start = date(2026, 10, 14, 12, 45)
        let stats = RouteStats(
            distanceMeters: 4_828.03, elevationGainMeters: 121, startedAt: start,
            endedAt: start.addingTimeInterval(5_760))
        #expect(
            RouteAttachText.spokenSummary(
                name: "Afternoon hike at Broken Arrow Trail", recorded: start, stats: stats,
                calendar: calendar)
                == "Afternoon hike at Broken Arrow Trail, recorded October 14, 3.0 miles, "
                + "397 feet gain, 1 hour, 36 minutes")
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}

// MARK: - Attach, replace, remove

@MainActor
struct RouteOperationsTests {
    private let container: ModelContainer
    private let context: ModelContext
    private let entry: Entry

    init() throws {
        container = try ModelContainerFactory.makeInMemory()
        context = ModelContext(container)
        let topic = Topic(title: "Sedona trip")
        context.insert(topic)
        entry = Entry(body: "Broken Arrow", topic: topic)
        context.insert(entry)
        try context.save()
    }

    @Test func attachGivesTheEntryOneRoute() throws {
        #expect(operations.attach(try draft("First"), to: entry, useStartAsLocation: false) == nil)
        #expect(entry.route?.name == "First")
        #expect(entry.hasRoute)
        #expect(try routeCount() == 1)
    }

    @Test func replacingDeletesTheOldRoute() throws {
        _ = operations.attach(try draft("First"), to: entry, useStartAsLocation: false)
        #expect(operations.attach(try draft("Second"), to: entry, useStartAsLocation: false) == nil)
        #expect(entry.route?.name == "Second")
        #expect(try context.fetch(FetchDescriptor<Route>()).map(\.name) == ["Second"])
    }

    @Test func removeLeavesNoRoute() throws {
        _ = operations.attach(try draft("First"), to: entry, useStartAsLocation: false)
        #expect(operations.removeRoute(from: entry) == nil)
        #expect(entry.route == nil)
        #expect(try routeCount() == 0)
    }

    @Test func routeStartBecomesTheLocationOnlyWhenAskedAndThereIsNone() throws {
        _ = operations.attach(try draft("Off"), to: entry, useStartAsLocation: false)
        #expect(!entry.hasLocation)

        _ = operations.attach(try draft("On"), to: entry, useStartAsLocation: true)
        #expect(entry.latitude == 34.84555)
        #expect(entry.longitude == -111.75681)
        #expect(entry.placeName == nil)
    }

    @Test func anExistingLocationIsNeverReplaced() throws {
        entry.latitude = 34.0
        entry.longitude = -111.0
        entry.placeName = "Sedona, AZ"
        try context.save()

        _ = operations.attach(try draft("Route"), to: entry, useStartAsLocation: true)
        #expect(entry.latitude == 34.0)
        #expect(entry.longitude == -111.0)
        #expect(entry.placeName == "Sedona, AZ")
    }

    @Test func trashingKeepsTheRouteAndPurgingDeletesIt() throws {
        _ = operations.attach(try draft("Route"), to: entry, useStartAsLocation: false)
        let trash = TrashOperations(context: context)
        #expect(trash.moveToTrash(entry) == nil)
        #expect(entry.route?.name == "Route")
        #expect(trash.restore(entry) == nil)
        #expect(entry.route?.name == "Route")

        #expect(trash.deletePermanently(entry) == nil)
        #expect(try routeCount() == 0)
    }

    private var operations: RouteOperations {
        RouteOperations(context: context)
    }

    private func routeCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<Route>())
    }

    private func draft(_ name: String) throws -> RouteDraft {
        let track = ParsedTrack(
            name: name,
            segments: [
                [
                    TrackPoint(latitude: 34.84555, longitude: -111.75681, elevation: 1_305),
                    TrackPoint(latitude: 34.846, longitude: -111.757, elevation: 1_312),
                ]
            ])
        return try RouteDraft(track: track, gpxData: Data(name.utf8), fileName: "\(name).gpx")
    }
}

// MARK: - Real fixture

/// Michael's AllTrails export of a Broken Arrow Trail hike. Skipped when the file isn't there.
struct BrokenArrowFixtureTests {
    static let url = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "Fixtures/Afternoon_hike_at_Broken_Arrow_Trail.gpx")

    @Test(.enabled(if: FileManager.default.fileExists(atPath: url.path(percentEncoded: false))))
    func matchesTheRecordedHike() async throws {
        let data = try Data(contentsOf: Self.url)
        let draft = try await GPXRouteImporter().makeRoute(
            from: data, fileName: Self.url.lastPathComponent)

        #expect(draft.name == "Afternoon hike at Broken Arrow Trail")
        let miles = draft.distanceMeters / 1_609.344
        #expect(abs(miles - 3.00) <= 0.05, "\(miles) mi")
        let minutes = try #require(draft.stats.duration) / 60
        #expect((95...97).contains(minutes), "\(minutes) min")
        let gain = try #require(draft.elevationGainMeters)
        #expect((115...135).contains(gain), "\(gain) m")
        #expect(abs((draft.startLatitude ?? 0) - 34.84555) < 1e-6)
        #expect(abs((draft.startLongitude ?? 0) - -111.75681) < 1e-6)
        #expect(try RoutePath.decode(draft.pathData).pointCount <= RouteLimits.maxPathPoints)
    }
}
