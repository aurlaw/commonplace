import CoreLocation
import MapKit
import SwiftUI

/// Where an entry was written: a small still map with a pin in the topic's color, and the place
/// underneath. Tapping it opens Apple Maps at the spot.
///
/// The place line is always shown, so the location is readable and tappable even when the map
/// has no tiles to draw (offline).
struct EntryLocationView: View {
    let entry: Entry

    var body: some View {
        if let latitude = entry.latitude, let longitude = entry.longitude {
            let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            let label = LocationLabel.text(
                placeName: entry.placeName, latitude: latitude, longitude: longitude
            )
            Button {
                openInMaps(center, name: entry.placeName)
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

    private func openInMaps(_ coordinate: CLLocationCoordinate2D, name: String?) {
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
