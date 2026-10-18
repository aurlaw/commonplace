import Foundation

/// Synthetic GPX tracks for the seed and previews, generated so no recorded track ships in the
/// app. Shapes are rough: a loop, an out-and-back, and a two-segment point-to-point.
nonisolated enum SampleRoutes {
    /// A loop around `center`, with a gentle climb and descent.
    static func loop(
        name: String, center: (Double, Double), radiusMeters: Double, climbMeters: Double,
        baseElevation: Double, start: Date, minutes: Double, points: Int = 240
    ) -> ParsedTrack {
        let track = (0...points).map { index -> TrackPoint in
            let fraction = Double(index) / Double(points)
            let angle = fraction * 2 * .pi
            // Not a perfect circle: trails bulge and wander.
            let radius = radiusMeters * (1 + 0.18 * sin(angle * 3))
            let metersPerDegreeLongitude = metersPerDegree * cos(center.0 * .pi / 180)
            return TrackPoint(
                latitude: center.0 + radius * cos(angle) / metersPerDegree,
                longitude: center.1 + radius * sin(angle) / metersPerDegreeLongitude,
                elevation: baseElevation + climbMeters * sin(angle / 2) + noise(index),
                time: start.addingTimeInterval(fraction * minutes * 60)
            )
        }
        return ParsedTrack(name: name, segments: [track])
    }

    /// Out to a high point and back the same way.
    static func outAndBack(
        name: String, from start: (Double, Double), bearingDegrees: Double, lengthMeters: Double,
        climbMeters: Double, baseElevation: Double, startTime: Date, minutes: Double,
        points: Int = 120
    ) -> ParsedTrack {
        let out = (0...points).map { index -> (Double, Double, Double) in
            let fraction = Double(index) / Double(points)
            let distance = lengthMeters * fraction
            let bearing = (bearingDegrees + 25 * sin(fraction * 5)) * .pi / 180
            return (
                start.0 + distance * cos(bearing) / metersPerDegree,
                start.1 + distance * sin(bearing) / (metersPerDegree * cos(start.0 * .pi / 180)),
                baseElevation + climbMeters * fraction * fraction
            )
        }
        let path = out + out.reversed().dropFirst()
        let track = path.enumerated().map { index, point in
            TrackPoint(
                latitude: point.0, longitude: point.1, elevation: point.2 + noise(index),
                time: startTime.addingTimeInterval(
                    Double(index) / Double(path.count - 1) * minutes * 60)
            )
        }
        return ParsedTrack(name: name, segments: [track])
    }

    /// From one point to another in two segments, with a pause between them (the watch was
    /// paused), so the gap isn't drawn or counted.
    static func pointToPoint(
        name: String, from start: (Double, Double), to end: (Double, Double),
        baseElevation: Double, climbMeters: Double, startTime: Date, minutes: Double,
        points: Int = 200
    ) -> ParsedTrack {
        let all = (0...points).map { index -> TrackPoint in
            let fraction = Double(index) / Double(points)
            let wander = 0.0015 * sin(fraction * 9)
            return TrackPoint(
                latitude: start.0 + (end.0 - start.0) * fraction + wander,
                longitude: start.1 + (end.1 - start.1) * fraction - wander,
                elevation: baseElevation + climbMeters * sin(fraction * .pi * 0.8) + noise(index),
                time: startTime.addingTimeInterval(fraction * minutes * 60)
            )
        }
        let split = points / 2
        return ParsedTrack(
            name: name, segments: [Array(all[..<split]), Array(all[(split + 4)...])])
    }

    /// A GPX 1.1 file for the track, as an export would look.
    static func gpx(_ track: ParsedTrack) -> Data {
        let times = Date.ISO8601FormatStyle()
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<gpx xmlns="http://www.topografix.com/GPX/1/1" version="1.1" creator="Commonplace sample">"#,
            "<trk>",
            "<name><![CDATA[\(track.name ?? "")]]></name>",
        ]
        for segment in track.segments {
            lines.append("<trkseg>")
            for point in segment {
                var line = #"<trkpt lat="\#(point.latitude)" lon="\#(point.longitude)">"#
                if let elevation = point.elevation {
                    line += "<ele>\((elevation * 100).rounded() / 100)</ele>"
                }
                if let time = point.time {
                    line += "<time>\(time.formatted(times))</time>"
                }
                lines.append(line + "</trkpt>")
            }
            lines.append("</trkseg>")
        }
        lines += ["</trk>", "</gpx>"]
        return Data(lines.joined(separator: "\n").utf8)
    }

    /// The seed's draft for a track; `nil` only if encoding fails.
    static func draft(_ track: ParsedTrack) -> RouteDraft? {
        try? RouteDraft(
            track: track, gpxData: gpx(track), fileName: "\(track.name ?? "Route").gpx")
    }

    // MARK: Seed tracks

    /// Cathedral Rock, Oct 2: short and steep, out to the saddle and back.
    static var cathedralRock: ParsedTrack {
        outAndBack(
            name: "Cathedral Rock at first light", from: (34.8253, -111.7885), bearingDegrees: 60,
            lengthMeters: 1_000, climbMeters: 210, baseElevation: 1_265,
            startTime: date(2026, 10, 2, 5, 48), minutes: 92)
    }

    /// Airport Mesa, Oct 4: the loop trail around the mesa.
    static var airportMesa: ParsedTrack {
        loop(
            name: "Airport Mesa loop", center: (34.8510, -111.7830), radiusMeters: 800,
            climbMeters: 45, baseElevation: 1_400, start: date(2026, 10, 4, 6, 15),
            minutes: 84)
    }

    /// Dolly Sods, Jun 14: hiking out from the Forks of Red Creek to Bear Rocks.
    static var dollySodsHikeOut: ParsedTrack {
        pointToPoint(
            name: "Hike out to Bear Rocks", from: (39.0170, -79.3540), to: (39.0637, -79.3035),
            baseElevation: 1_080, climbMeters: 150, startTime: date(2026, 6, 14, 9, 30),
            minutes: 185)
    }

    private static let metersPerDegree = 111_195.0

    /// Local time, like `SampleData.date`, which is main-actor isolated.
    private static func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int
    ) -> Date {
        let components = DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute)
        return Calendar.current.date(from: components) ?? .distantPast
    }

    /// A few meters of deterministic GPS-style jitter.
    private static func noise(_ index: Int) -> Double {
        sin(Double(index) * 12.9898) * 1.6
    }
}

/// A `RouteImporter` with a fixed answer, for previews and UI tests. Never parses.
nonisolated struct FakeRouteImporter: RouteImporter {
    var result: Result<RouteDraft, GPXError>
    var delay = Duration.zero

    init(result: Result<RouteDraft, GPXError>? = nil, delay: Duration = .zero) {
        self.result =
            result ?? SampleRoutes.draft(SampleRoutes.cathedralRock).map { .success($0) }
            ?? .failure(.noTrack)
        self.delay = delay
    }

    func makeRoute(from data: Data, fileName: String) async throws -> RouteDraft {
        try await Task.sleep(for: delay)
        return try result.get()
    }
}
