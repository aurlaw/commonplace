import CoreLocation
import Foundation
import MapKit

/// A pin to group: an entry's ID and coordinates.
nonisolated struct MapPin<ID: Hashable>: Equatable {
    let id: ID
    let latitude: Double
    let longitude: Double
}

/// One or more pins drawn as one mark: a single pin, or a count bubble at the members' centroid.
nonisolated struct MapGroup<ID: Hashable>: Equatable {
    /// In input order; the first is the group's seed.
    var members: [ID]
    var latitude: Double
    var longitude: Double

    var count: Int { members.count }
    var isSingle: Bool { members.count == 1 }
}

/// What a topic's map shows, and how its pins fit and group.
nonisolated enum TopicMapModel {
    /// Pins closer than this on screen, in points, share a bubble.
    static let groupingDistance = 44.0
    /// The narrowest span the camera is fitted to, in meters: what a single pin gets.
    static let minimumSpanMeters = 1_000.0
    /// When the visible width is this narrow, in meters, nothing groups, so even entries at the
    /// same spot come apart.
    static let ungroupedWidthMeters = 300.0
    /// Tapping a bubble fits its members at least this wide, below `ungroupedWidthMeters`, so
    /// the tap always splits it.
    static let groupZoomSpanMeters = 200.0
    /// How much wider than the pins' bounding box the fitted region is.
    static let padding = 1.4

    private static let metersPerDegree = 111_320.0

    /// Live entries with both coordinates, newest first (ties by `createdAt`).
    static func locatedEntries(for topic: Topic) -> [Entry] {
        topic.liveEntries
            .filter { $0.isLive && $0.hasLocation }
            .sorted {
                $0.date != $1.date ? $0.date > $1.date : $0.createdAt > $1.createdAt
            }
    }

    /// Every live entry in the topic, located or not: the "of M" in the caption.
    static func liveEntryCount(for topic: Topic) -> Int {
        topic.liveEntries.filter(\.isLive).count
    }

    /// "12 of 23 entries have a location", "1 of 5 entries has a location".
    static func caption(located: Int, total: Int) -> String {
        let noun = total == 1 ? "entry" : "entries"
        let verb = located == 1 ? "has" : "have"
        return "\(located) of \(total) \(noun) \(verb) a location"
    }

    /// "5 entries near Cathedral Rock, zoom in"
    static func groupLabel(count: Int, near place: String) -> String {
        "\(count) entries near \(place), zoom in"
    }

    /// The first non-blank line of the entry's plain text, or `nil` when there is none.
    static func firstLine(of body: String) -> String? {
        SearchableText.plain(body)
            .split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    /// The region that shows every coordinate: the bounding box widened by `padding`, and at
    /// least `minimumMeters` across. `nil` for no coordinates.
    ///
    /// Points either side of the antimeridian are treated as far apart (the box spans the
    /// world the long way); a topic's entries are expected to be on one side.
    static func fittingRegion(
        for coordinates: [CLLocationCoordinate2D], minimumMeters: Double = minimumSpanMeters
    ) -> MKCoordinateRegion? {
        guard let first = coordinates.first else { return nil }
        var minLatitude = first.latitude
        var maxLatitude = first.latitude
        var minLongitude = first.longitude
        var maxLongitude = first.longitude
        for coordinate in coordinates.dropFirst() {
            minLatitude = min(minLatitude, coordinate.latitude)
            maxLatitude = max(maxLatitude, coordinate.latitude)
            minLongitude = min(minLongitude, coordinate.longitude)
            maxLongitude = max(maxLongitude, coordinate.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let minimumLatitudeDelta = minimumMeters / metersPerDegree
        let minimumLongitudeDelta =
            minimumMeters / (metersPerDegree * max(cos(center.latitude * .pi / 180), 0.01))
        let span = MKCoordinateSpan(
            latitudeDelta: min(
                max((maxLatitude - minLatitude) * padding, minimumLatitudeDelta), 180),
            longitudeDelta: min(
                max((maxLongitude - minLongitude) * padding, minimumLongitudeDelta), 360)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    /// The visible width of `region` in meters, measured at its center.
    static func widthMeters(of region: MKCoordinateRegion) -> Double {
        region.span.longitudeDelta * metersPerDegree * cos(region.center.latitude * .pi / 180)
    }

    /// Groups pins that would be closer than `distance` points on a map `mapWidth` points wide
    /// showing `region`.
    ///
    /// Distances are measured in Web Mercator world space, so groups depend only on the zoom,
    /// not on where the map is panned. Greedy: each pin joins the first group whose seed (its
    /// first pin) is near enough, otherwise starts one. At `ungroupedWidthMeters` or closer,
    /// every pin stands alone.
    static func groups<ID: Hashable>(
        _ pins: [MapPin<ID>], region: MKCoordinateRegion, mapWidth: Double,
        distance: Double = groupingDistance
    ) -> [MapGroup<ID>] {
        let singles = pins.map {
            MapGroup(members: [$0.id], latitude: $0.latitude, longitude: $0.longitude)
        }
        guard mapWidth > 0, region.span.longitudeDelta > 0,
            widthMeters(of: region) > ungroupedWidthMeters
        else {
            return singles
        }
        // One world unit is the full 360° of longitude.
        let threshold = distance / mapWidth * (region.span.longitudeDelta / 360)

        var seeds: [(x: Double, y: Double)] = []
        var members: [[MapPin<ID>]] = []
        for pin in pins {
            let point = worldPoint(latitude: pin.latitude, longitude: pin.longitude)
            if let index = seeds.firstIndex(where: {
                hypot($0.x - point.x, $0.y - point.y) < threshold
            }) {
                members[index].append(pin)
            } else {
                seeds.append(point)
                members.append([pin])
            }
        }
        return members.map { group in
            MapGroup(
                members: group.map(\.id),
                latitude: group.map(\.latitude).reduce(0, +) / Double(group.count),
                longitude: group.map(\.longitude).reduce(0, +) / Double(group.count)
            )
        }
    }

    /// Web Mercator, both axes 0…1 across the world.
    private static func worldPoint(latitude: Double, longitude: Double) -> (x: Double, y: Double) {
        let clamped = min(max(latitude, -85), 85) * .pi / 180
        return (
            x: (longitude + 180) / 360,
            y: 0.5 - log(tan(.pi / 4 + clamped / 2)) / (2 * .pi)
        )
    }
}

/// The topic map's base layer: a per-device preference, not synced.
nonisolated enum TopicMapStyle: String, CaseIterable, Identifiable {
    case standard
    case hybrid
    case satellite

    static let storageKey = "topicMapStyle"
    static let defaultValue = TopicMapStyle.standard

    /// An unknown stored value falls back to Standard.
    init(storedValue: String) {
        self = TopicMapStyle(rawValue: storedValue) ?? Self.defaultValue
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .hybrid: "Hybrid"
        case .satellite: "Satellite"
        }
    }
}
