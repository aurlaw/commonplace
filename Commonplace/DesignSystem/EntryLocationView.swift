import CoreLocation
import MapKit
import SwiftUI

/// Where an entry was written: a small still map with a pin in the topic's color, and the place
/// underneath. Tapping it opens Apple Maps at the spot.
///
/// With a route (I16), the map also draws the track, fitted to it and the pin, with the stats
/// underneath, and tapping it opens the Route view instead; an entry with a route and no
/// location still shows it, without a pin.
///
/// The place line is always shown, so the location is readable and tappable even when the map
/// has no tiles to draw (offline).
struct EntryLocationView: View {
    let entry: Entry

    var body: some View {
        if let route = entry.route {
            EntryRouteMap(entry: entry, route: route)
        } else if let latitude = entry.latitude, let longitude = entry.longitude {
            let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            let label = LocationLabel.text(
                placeName: entry.placeName, latitude: latitude, longitude: longitude
            )
            Button {
                MapsApp.open(center, name: entry.placeName)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Map(
                        initialPosition: .region(
                            MKCoordinateRegion(
                                center: center, latitudinalMeters: 1_500, longitudinalMeters: 1_500
                            )
                        ),
                        interactionModes: []
                    ) {
                        Marker(label, coordinate: center)
                            .tint(entry.topic?.tint ?? .accentColor)
                    }
                    // The camera is set once, so a changed location needs a new map.
                    .id("\(latitude),\(longitude)")
                    .frame(height: 160)
                    .clipShape(.rect(cornerRadius: 14))
                    .allowsHitTesting(false)
                    Label(label, systemImage: "location.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Location: \(label). Opens in Maps.")
            .accessibilityAddTraits(.isButton)
        }
    }
}

/// The entry detail map for an entry with a route. Still, like the location map; tapping it
/// pushes the Route view.
private struct EntryRouteMap: View {
    let entry: Entry
    let route: Route

    /// Decoded from `pathData` off the main actor, only once this page is on screen.
    @State private var segments: [[Coordinate]] = []

    var body: some View {
        let pin = entry.locationCoordinate
        let label = pin.map {
            LocationLabel.text(
                placeName: entry.placeName, latitude: $0.latitude, longitude: $0.longitude)
        }
        NavigationLink(value: AppRoute.route(entry)) {
            VStack(alignment: .leading, spacing: 8) {
                Map(
                    initialPosition: RouteCamera.region(segments: segments, pin: pin)
                        .map { .region($0) } ?? .automatic,
                    interactionModes: []
                ) {
                    RoutePolylines(segments: segments, tint: tint)
                    if let pin, let label {
                        Marker(label, coordinate: pin.clLocation)
                            .tint(tint)
                    }
                }
                // The camera is set once, so a newly decoded path or a moved pin needs a new map.
                .id(MapKey(points: segments.reduce(0) { $0 + $1.count }, pin: pin))
                .frame(height: 160)
                .clipShape(.rect(cornerRadius: 14))
                .allowsHitTesting(false)
                if let label {
                    Label(label, systemImage: "location.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                RouteStatsRow(stats: route.stats)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(place: label))
        .accessibilityAddTraits(.isButton)
        .task(id: route.pathData) {
            segments = await RoutePathDecoder.coordinates(from: route.pathData)
        }
    }

    private var tint: Color {
        entry.topic?.tint ?? .accentColor
    }

    /// "Location: Broken Arrow Trailhead. Route, 3.0 miles, 397 feet gain. Opens route."
    private func accessibilityText(place: String?) -> String {
        let stats = route.stats.spokenSummary(includesTime: false)
        let location = place.map { "Location: \($0). " } ?? ""
        return "\(location)Route, \(stats). Opens route."
    }

    private struct MapKey: Hashable {
        let points: Int
        let latitude: Double?
        let longitude: Double?

        init(points: Int, pin: Coordinate?) {
            self.points = points
            latitude = pin?.latitude
            longitude = pin?.longitude
        }
    }
}

/// Apple Maps, opened at a spot.
enum MapsApp {
    static func open(_ coordinate: CLLocationCoordinate2D, name: String?) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let item = MKMapItem(location: location, address: nil)
        item.name = name
        item.openInMaps()
    }
}

#Preview("Light") {
    EntryLocationPreview()
}

#Preview("Dark") {
    EntryLocationPreview()
        .preferredColorScheme(.dark)
}

/// One entry with a place name and one with coordinates only.
private struct EntryLocationPreview: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ForEach([2, 1], id: \.self) { index in
                    if let entry = PreviewContainer.entry(in: "Sedona trip", at: index) {
                        EntryLocationView(entry: entry)
                    }
                }
            }
            .padding(20)
        }
        .sampleData()
    }
}
