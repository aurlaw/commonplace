import Foundation

/// Distance, elevation, time, and the stored drawing path and profile, computed from a parsed
/// track. Pure; no MapKit types.
nonisolated enum RouteMetrics {
    /// Mean Earth radius for haversine distances, in meters.
    static let earthRadius = 6_371_000.0

    /// Great-circle distance between two points, in meters.
    static func haversine(
        _ a: (latitude: Double, longitude: Double), _ b: (latitude: Double, longitude: Double)
    ) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h =
            sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    /// The sum of distances between consecutive points within each segment; the gap between
    /// one segment's end and the next one's start isn't counted.
    static func distance(segments: [[TrackPoint]]) -> Double {
        segments.reduce(0) { total, segment in
            total
                + zip(segment, segment.dropFirst()).reduce(0) {
                    $0 + haversine($1.0.pair, $1.1.pair)
                }
        }
    }

    /// Elevation gain with a hysteresis filter, across all segments in order; points without an
    /// elevation are skipped. `nil` when no point has one.
    ///
    /// `ref` starts at the first elevation. A rise of `threshold` or more above `ref` adds the
    /// rise and moves `ref` up; a fall of `threshold` or more moves `ref` down; anything
    /// smaller is noise.
    static func elevationGain(
        segments: [[TrackPoint]], threshold: Double = RouteLimits.elevationThreshold
    ) -> Double? {
        let elevations = segments.joined().compactMap(\.elevation)
        guard var reference = elevations.first else { return nil }
        var gain = 0.0
        for elevation in elevations.dropFirst() {
            if elevation - reference >= threshold {
                gain += elevation - reference
                reference = elevation
            } else if reference - elevation >= threshold {
                reference = elevation
            }
        }
        return gain
    }

    static func minElevation(segments: [[TrackPoint]]) -> Double? {
        segments.joined().compactMap(\.elevation).min()
    }

    static func maxElevation(segments: [[TrackPoint]]) -> Double? {
        segments.joined().compactMap(\.elevation).max()
    }

    /// The first timestamp in the track.
    static func startTime(segments: [[TrackPoint]]) -> Date? {
        segments.joined().lazy.compactMap(\.time).first
    }

    /// The last timestamp in the track.
    static func endTime(segments: [[TrackPoint]]) -> Date? {
        segments.joined().reversed().lazy.compactMap(\.time).first
    }

    static func startCoordinate(segments: [[TrackPoint]]) -> Coordinate? {
        segments.joined().first.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
    }

    // MARK: Drawing path

    /// Each segment simplified with Douglas–Peucker at `tolerance` meters; the tolerance is
    /// doubled until the whole path has at most `maxPoints`. Segments stay separate, so a gap
    /// is never drawn as a straight line.
    static func simplifiedPath(
        segments: [[TrackPoint]], tolerance: Double = RouteLimits.pathTolerance,
        maxPoints: Int = RouteLimits.maxPathPoints
    ) -> RoutePath {
        let all = Array(segments.joined())
        guard !all.isEmpty else { return RoutePath(segments: []) }
        // A local equirectangular projection, in meters, around the track's mean latitude.
        let meanLatitude = all.reduce(0) { $0 + $1.latitude } / Double(all.count)
        let metersPerDegreeLatitude = earthRadius * .pi / 180
        let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(meanLatitude * .pi / 180)
        let projected = segments.map { segment in
            segment.map {
                (
                    x: $0.longitude * metersPerDegreeLongitude,
                    y: $0.latitude * metersPerDegreeLatitude
                )
            }
        }

        var tolerance = tolerance
        var kept: [[Int]] = []
        repeat {
            kept = projected.map { douglasPeucker($0, tolerance: tolerance) }
            tolerance *= 2
        } while kept.reduce(0, { $0 + $1.count }) > maxPoints && tolerance < 1e8

        return RoutePath(
            segments: zip(segments, kept).map { segment, indices in
                indices.map { [segment[$0].latitude, segment[$0].longitude] }
            }
        )
    }

    /// Indices of the points kept, in order. Iterative, so long tracks can't overflow the stack.
    static func douglasPeucker(_ points: [(x: Double, y: Double)], tolerance: Double) -> [Int] {
        guard points.count > 2 else { return Array(points.indices) }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack = [(0, points.count - 1)]
        while let (start, end) = stack.popLast() {
            guard end > start + 1 else { continue }
            var farthest = start
            var farthestDistance = 0.0
            for index in (start + 1)..<end {
                let distance = perpendicularDistance(points[index], points[start], points[end])
                if distance > farthestDistance {
                    farthest = index
                    farthestDistance = distance
                }
            }
            if farthestDistance > tolerance {
                keep[farthest] = true
                stack.append((start, farthest))
                stack.append((farthest, end))
            }
        }
        return keep.indices.filter { keep[$0] }
    }

    /// Distance from `point` to the segment `a`–`b`.
    private static func perpendicularDistance(
        _ point: (x: Double, y: Double), _ a: (x: Double, y: Double), _ b: (x: Double, y: Double)
    ) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
        return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
    }

    // MARK: Elevation profile

    /// `samples` points of (distance along the track, elevation), evenly spaced by distance
    /// from 0 to the full distance, interpolated between points that have an elevation.
    /// `nil` when no point has an elevation or the track has no length.
    static func profile(
        segments: [[TrackPoint]], samples: Int = RouteLimits.profileSamples
    ) -> RouteProfile? {
        // Cumulative distance at every point that has an elevation; gaps aren't counted.
        var known: [(distance: Double, elevation: Double)] = []
        var travelled = 0.0
        for segment in segments {
            for (index, point) in segment.enumerated() {
                if index > 0 {
                    travelled += haversine(segment[index - 1].pair, point.pair)
                }
                if let elevation = point.elevation {
                    known.append((travelled, elevation))
                }
            }
        }
        guard let first = known.first, let last = known.last, travelled > 0, samples >= 2 else {
            return nil
        }

        var result: [[Double]] = []
        result.reserveCapacity(samples)
        var cursor = 0
        for step in 0..<samples {
            let distance = travelled * Double(step) / Double(samples - 1)
            let elevation: Double
            if distance <= first.distance {
                elevation = first.elevation
            } else if distance >= last.distance {
                elevation = last.elevation
            } else {
                while known[cursor + 1].distance < distance {
                    cursor += 1
                }
                let a = known[cursor]
                let b = known[cursor + 1]
                let span = b.distance - a.distance
                let rise = (b.elevation - a.elevation) * (distance - a.distance)
                elevation = span > 0 ? a.elevation + rise / span : b.elevation
            }
            result.append([distance, elevation])
        }
        return RouteProfile(samples: result)
    }
}

extension TrackPoint {
    fileprivate nonisolated var pair: (latitude: Double, longitude: Double) {
        (latitude, longitude)
    }
}

/// The stored drawing path: per segment, `[latitude, longitude]` pairs.
nonisolated struct RoutePath: Codable, Sendable, Equatable {
    var segments: [[[Double]]]

    var pointCount: Int { segments.reduce(0) { $0 + $1.count } }

    /// Per segment, the points as coordinates (malformed pairs are skipped).
    var coordinates: [[Coordinate]] {
        segments.map { segment in
            segment.compactMap { pair in
                pair.count == 2 ? Coordinate(latitude: pair[0], longitude: pair[1]) : nil
            }
        }
    }

    func encoded() throws -> Data {
        try RouteEncoding.encode(self)
    }

    static func decode(_ data: Data) throws -> RoutePath {
        try RouteEncoding.decode(RoutePath.self, from: data)
    }
}

/// The stored elevation profile: `[distance meters, elevation meters]` samples.
nonisolated struct RouteProfile: Codable, Sendable, Equatable {
    var samples: [[Double]]

    /// The samples as values; malformed ones are skipped.
    var points: [(distance: Double, elevation: Double)] {
        samples.compactMap { $0.count == 2 ? ($0[0], $0[1]) : nil }
    }

    func encoded() throws -> Data {
        try RouteEncoding.encode(self)
    }

    static func decode(_ data: Data) throws -> RouteProfile {
        try RouteEncoding.decode(RouteProfile.self, from: data)
    }
}

/// Binary property lists: compact, and Foundation-only.
nonisolated enum RouteEncoding {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try PropertyListDecoder().decode(type, from: data)
    }
}
