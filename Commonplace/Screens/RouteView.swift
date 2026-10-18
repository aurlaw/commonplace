import MapKit
import SwiftUI

/// An entry's route, full screen: an interactive map of the track with its start and the
/// entry's pin, then the name, recorded date, stats, elevation profile, and Open in Maps for
/// the entry's location (Apple Maps can't show the track itself).
///
/// Drawn from the cached `pathData` and `profileData`; the GPX file is never read here.
struct RouteView: View {
    let entry: Entry

    var body: some View {
        // The screen outlives its entry, or the route, for a moment after a delete.
        if entry.isAvailable, let route = entry.route, route.isAvailable {
            RouteContent(entry: entry, route: route)
        } else {
            ContentUnavailableView("No Route", systemImage: RouteSymbol.name)
        }
    }
}

private struct RouteContent: View {
    let entry: Entry
    let route: Route

    @Environment(\.locationService) private var locationService
    @State private var segments: [[Coordinate]] = []
    @State private var profile: RouteProfile?
    @State private var position = MapCameraPosition.automatic
    @State private var showsUserLocation = false

    var body: some View {
        Map(position: $position) {
            RoutePolylines(segments: segments, tint: tint, lineWidth: 5)
            if let start = segments.first?.first {
                Marker("Start", systemImage: "flag.fill", coordinate: start.clLocation)
                    .tint(.green)
            }
            if let pin = entry.locationCoordinate {
                Marker(placeLabel ?? "Entry", coordinate: pin.clLocation)
                    .tint(tint)
            }
            if showsUserLocation {
                UserAnnotation()
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
            if showsUserLocation {
                MapUserLocationButton()
            }
        }
        .safeAreaInset(edge: .bottom) {
            panel
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: route.pathData) {
            segments = await RoutePathDecoder.coordinates(from: route.pathData)
            if let region = RouteCamera.region(segments: segments, pin: entry.locationCoordinate) {
                position = .region(region)
            }
        }
        .task(id: route.profileData) {
            profile = await RoutePathDecoder.profile(from: route.profileData)
        }
        .onAppear {
            // Never asks: the dot only shows when access is already granted.
            showsUserLocation = locationService.isAuthorized
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(route.name)
                    .font(.headline)
                    .lineLimit(2)
                if let recorded = route.startedAt {
                    Text("Recorded \(EntryTimeline.fullDate(recorded))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            RouteStatsRow(stats: route.stats)

            if let profile, profile.points.count >= 2 {
                RouteElevationChart(profile: profile, tint: tint)
                    .frame(height: 120)
            }

            if let pin = entry.locationCoordinate {
                Button("Open in Maps", systemImage: "map") {
                    MapsApp.open(pin.clLocation, name: entry.placeName)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Opens the entry’s location in Maps")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: .rect(cornerRadius: 24))
        .shadow(color: .black.opacity(0.12), radius: 12, y: -2)
        .padding(.horizontal, 8)
    }

    private var tint: Color {
        entry.topic?.tint ?? .accentColor
    }

    private var placeLabel: String? {
        entry.locationCoordinate.map {
            LocationLabel.text(
                placeName: entry.placeName, latitude: $0.latitude, longitude: $0.longitude)
        }
    }
}

#Preview("Light") {
    RoutePreview()
}

#Preview("Dark") {
    RoutePreview()
        .preferredColorScheme(.dark)
}

#Preview("No location") {
    RoutePreview(topic: "Dolly Sods", index: 2)
}

#Preview("No location · Dark") {
    RoutePreview(topic: "Dolly Sods", index: 2)
        .preferredColorScheme(.dark)
}

private struct RoutePreview: View {
    /// Cathedral Rock by default, which has a route and a location.
    var topic = "Sedona trip"
    var index = 2

    var body: some View {
        NavigationStack {
            if let entry = PreviewContainer.entry(in: topic, at: index) {
                RouteView(entry: entry)
            }
        }
        .sampleData()
    }
}
