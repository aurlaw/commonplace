import Foundation

/// Size limits for imported GPX files and what is stored from them, in one place.
nonisolated enum RouteLimits {
    /// Larger files are rejected before parsing.
    static let maxFileBytes = 10 * 1024 * 1024
    /// Tracks with more points are rejected.
    static let maxPoints = 50_000
    /// The stored drawing path is simplified until it has at most this many points.
    static let maxPathPoints = 2_000
    /// Douglas–Peucker tolerance for the drawing path, in meters, before any raising.
    static let pathTolerance = 5.0
    /// Samples in the stored elevation profile.
    static let profileSamples = 200
    /// Elevation changes smaller than this, in meters, are treated as GPS noise.
    static let elevationThreshold = 5.0
}

/// One point of a GPX track.
nonisolated struct TrackPoint: Sendable, Equatable {
    var latitude: Double
    var longitude: Double
    /// Meters; `nil` when the point has no `<ele>`.
    var elevation: Double?
    var time: Date?
}

/// What `GPXParser` reads from a file: the track's name and its points, one array per segment.
nonisolated struct ParsedTrack: Sendable, Equatable {
    var name: String?
    var segments: [[TrackPoint]]

    var pointCount: Int { segments.reduce(0) { $0 + $1.count } }
}

nonisolated enum GPXError: Error, Equatable {
    case tooLarge
    /// Not XML, or XML whose root isn't `<gpx>`.
    case notGPX
    /// Fewer than two track (or route) points.
    case noTrack
    case tooManyPoints

    /// For the import alert.
    var message: String {
        switch self {
        case .tooLarge: "This file is larger than 10 MB."
        case .notGPX: "This file isn’t a GPX file."
        case .noTrack: "This file doesn’t contain a track."
        case .tooManyPoints: "This track has more than 50,000 points."
        }
    }
}

/// Reads GPX 1.1 with Foundation's `XMLParser`.
///
/// Every `<trk>/<trkseg>/<trkpt>` is read, in order, one segment per `<trkseg>`. With no track
/// points, the `<rte>/<rtept>` points become a single segment. Waypoints, extensions, and
/// unknown elements are ignored. The name is the first `<trk><name>` (else `<rte><name>`),
/// CDATA included.
nonisolated enum GPXParser {
    static func parse(_ data: Data) throws(GPXError) -> ParsedTrack {
        guard data.count <= RouteLimits.maxFileBytes else { throw .tooLarge }
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = reader
        let finished = parser.parse()

        if let error = reader.error {
            throw error
        }
        guard finished, reader.sawRoot else { throw .notGPX }

        let segments = reader.trackSegments.filter { !$0.isEmpty }
        let track =
            segments.isEmpty
            ? ParsedTrack(
                name: reader.routeName,
                segments: reader.routePoints.isEmpty ? [] : [reader.routePoints])
            : ParsedTrack(name: reader.trackName ?? reader.routeName, segments: segments)
        guard track.pointCount >= 2 else { throw .noTrack }
        return track
    }

    /// "2026-10-14T19:45:08Z", with or without fractional seconds.
    static func date(from string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = try? Date(trimmed, strategy: .iso8601) {
            return date
        }
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return try? Date(trimmed, strategy: fractional)
    }

    /// Lives only for one synchronous `parse()`, on the caller's thread.
    private nonisolated final class Reader: NSObject, XMLParserDelegate {
        var sawRoot = false
        var error: GPXError?
        var trackName: String?
        var routeName: String?
        var trackSegments: [[TrackPoint]] = []
        var routePoints: [TrackPoint] = []

        /// Open elements, innermost last.
        private var path: [String] = []
        private var point: TrackPoint?
        private var text = ""
        private var count = 0

        func parser(
            _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
            qualifiedName: String?, attributes: [String: String] = [:]
        ) {
            if path.isEmpty {
                guard elementName == "gpx" else {
                    parser.abortParsing()
                    return
                }
                sawRoot = true
            }
            let parent = path.last
            path.append(elementName)
            text = ""

            switch (elementName, parent) {
            case ("trkseg", "trk"):
                trackSegments.append([])
            case ("trkpt", "trkseg"), ("rtept", "rte"):
                count += 1
                guard count <= RouteLimits.maxPoints else {
                    error = .tooManyPoints
                    parser.abortParsing()
                    return
                }
                if let latitude = attributes["lat"].flatMap(Double.init),
                    let longitude = attributes["lon"].flatMap(Double.init),
                    (-90...90).contains(latitude), (-180...180).contains(longitude)
                {
                    point = TrackPoint(latitude: latitude, longitude: longitude)
                } else {
                    point = nil
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, foundCDATA block: Data) {
            text += String(decoding: block, as: UTF8.self)
        }

        func parser(
            _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
            qualifiedName: String?
        ) {
            path.removeLast()
            let parent = path.last
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            text = ""

            switch (elementName, parent) {
            case ("ele", "trkpt"), ("ele", "rtept"):
                point?.elevation = Double(value)
            case ("time", "trkpt"), ("time", "rtept"):
                point?.time = GPXParser.date(from: value)
            case ("name", "trk") where trackName == nil && !value.isEmpty:
                trackName = value
            case ("name", "rte") where routeName == nil && !value.isEmpty:
                routeName = value
            case ("trkpt", _):
                if let point, !trackSegments.isEmpty {
                    trackSegments[trackSegments.count - 1].append(point)
                }
                point = nil
            case ("rtept", _):
                if let point {
                    routePoints.append(point)
                }
                point = nil
            default:
                break
            }
        }
    }
}
