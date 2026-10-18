import MapKit
import SwiftData
import SwiftUI

/// A topic's located entries on one map: pins in the topic's color, grouped into count bubbles
/// when close, and a preview card for the selected pin.
///
/// Never asks for location access: the user-location button and dot appear only when access is
/// already granted.
struct TopicMapView: View {
    let topic: Topic

    var body: some View {
        // The screen outlives its topic for a moment after a permanent delete.
        if topic.isAvailable {
            TopicMapContent(topic: topic)
        }
    }
}

private struct TopicMapContent: View {
    let topic: Topic

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locationService) private var locationService
    @Environment(\.referenceDate) private var referenceDate
    @AppStorage(TopicMapStyle.storageKey) private var storedStyle =
        TopicMapStyle.defaultValue.rawValue
    @State private var position: MapCameraPosition
    /// The region on screen once the camera settles; grouping is recomputed from it.
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var mapWidth = 0.0
    @State private var selection: PersistentIdentifier?
    @State private var showsUserLocation = false
    @AccessibilityFocusState private var isCardFocused: Bool

    init(topic: Topic) {
        self.topic = topic
        let coordinates = TopicMapModel.locatedEntries(for: topic).compactMap(\.coordinate)
        let region = TopicMapModel.fittingRegion(for: coordinates)
        _position = State(initialValue: region.map { .region($0) } ?? .automatic)
        _visibleRegion = State(initialValue: region)
    }

    var body: some View {
        let entries = TopicMapModel.locatedEntries(for: topic)
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Entries with a Location",
                    systemImage: "mappin.slash",
                    description: Text("Entries saved with a location appear on the map.")
                )
            } else {
                map(entries)
                    .safeAreaInset(edge: .bottom) {
                        bottomBar(entries)
                            .animation(reduceMotion ? nil : .default, value: selection)
                    }
            }
        }
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                styleMenu
            }
        }
        .onAppear {
            showsUserLocation = locationService.isAuthorized
        }
        // After a selection, VoiceOver moves to the card instead of staying on the map.
        .onChange(of: selection) { _, id in
            isCardFocused = id != nil
        }
        // A selected entry that leaves the map (trashed, moved, location removed) closes its card.
        .onChange(of: entries.map(\.persistentModelID)) { _, ids in
            if let selection, !ids.contains(selection) {
                self.selection = nil
            }
        }
    }

    private func map(_ entries: [Entry]) -> some View {
        let groups = groups(of: entries)
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.persistentModelID, $0) })
        return Map(position: $position, selection: $selection) {
            if showsUserLocation {
                UserAnnotation()
            }
            ForEach(groups, id: \.members) { group in
                if group.isSingle, let entry = byID[group.members[0]] {
                    // The title is the pin's VoiceOver label; it is hidden on the map, where
                    // dates and places would crowd each other.
                    Marker(pinLabel(entry), systemImage: "text.quote", coordinate: group.coordinate)
                        .tint(topic.tint)
                        .tag(entry.persistentModelID)
                } else {
                    let title = groupTitle(group, byID: byID)
                    Annotation(coordinate: group.coordinate) {
                        GroupBubble(count: group.count, tint: topic.tint) {
                            zoom(to: group, byID: byID)
                        }
                        .accessibilityLabel(title)
                    } label: {
                        Text(title)
                    }
                }
            }
            .annotationTitles(.hidden)
        }
        .mapStyle(mapStyle)
        .mapControls {
            MapCompass()
            MapScaleView()
            if showsUserLocation {
                MapUserLocationButton()
            }
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
        }
        .onGeometryChange(for: Double.self) { proxy in
            Double(proxy.size.width)
        } action: { width in
            mapWidth = width
        }
        .onChange(of: selection) { _, id in
            guard let id, let entry = byID[id] else { return }
            reveal(entry)
        }
    }

    @ViewBuilder
    private func bottomBar(_ entries: [Entry]) -> some View {
        if let selection, let entry = entries.first(where: { $0.persistentModelID == selection }) {
            EntryMapCard(entry: entry, now: referenceDate ?? .now)
                .accessibilityFocused($isCardFocused)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(
                    reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        } else {
            Text(
                TopicMapModel.caption(
                    located: entries.count, total: TopicMapModel.liveEntryCount(for: topic))
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.background, in: .capsule)
            .padding(.bottom, 8)
        }
    }

    private var styleMenu: some View {
        Menu {
            Picker("Map Style", selection: $storedStyle) {
                ForEach(TopicMapStyle.allCases) { style in
                    Text(style.title).tag(style.rawValue)
                }
            }
        } label: {
            Label("Map Style", systemImage: "map")
        }
    }

    private var mapStyle: MapStyle {
        switch TopicMapStyle(storedValue: storedStyle) {
        case .standard: .standard
        case .hybrid: .hybrid
        case .satellite: .imagery
        }
    }

    private func groups(of entries: [Entry]) -> [MapGroup<PersistentIdentifier>] {
        let pins = entries.compactMap { entry in
            entry.coordinate.map {
                MapPin(id: entry.persistentModelID, latitude: $0.latitude, longitude: $0.longitude)
            }
        }
        guard let visibleRegion else {
            return TopicMapModel.groups(pins, region: MKCoordinateRegion(), mapWidth: 0)
        }
        return TopicMapModel.groups(pins, region: visibleRegion, mapWidth: mapWidth)
    }

    /// "Oct 2, 6:10 AM, Cathedral Rock"
    private func pinLabel(_ entry: Entry) -> String {
        let date = EntryTimeline.dateAndTime(entry.date, now: referenceDate ?? .now)
        return "\(date), \(place(of: entry))"
    }

    /// Named after its newest entry's place.
    private func groupTitle(
        _ group: MapGroup<PersistentIdentifier>, byID: [PersistentIdentifier: Entry]
    ) -> String {
        let place = byID[group.members[0]].map(place(of:)) ?? ""
        return TopicMapModel.groupLabel(count: group.count, near: place)
    }

    private func place(of entry: Entry) -> String {
        LocationLabel.text(
            placeName: entry.placeName, latitude: entry.latitude ?? 0,
            longitude: entry.longitude ?? 0)
    }

    /// Fits the bubble's entries, close enough that they come apart.
    private func zoom(
        to group: MapGroup<PersistentIdentifier>, byID: [PersistentIdentifier: Entry]
    ) {
        let coordinates = group.members.compactMap { byID[$0]?.coordinate }
        guard
            let region = TopicMapModel.fittingRegion(
                for: coordinates, minimumMeters: TopicMapModel.groupZoomSpanMeters)
        else { return }
        withAnimation(reduceMotion ? nil : .default) {
            position = .region(region)
        }
    }

    /// Centers the selected pin at the current zoom, above the card (the card is a bottom safe
    /// area inset, and the map centers within its safe area).
    private func reveal(_ entry: Entry) {
        guard let coordinate = entry.coordinate, let visibleRegion else { return }
        withAnimation(reduceMotion ? nil : .default) {
            position = .region(MKCoordinateRegion(center: coordinate, span: visibleRegion.span))
        }
    }
}

/// A count bubble in the topic's color. Tapping it zooms in.
private struct GroupBubble: View {
    let count: Int
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(count)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(minWidth: 34, minHeight: 34)
                .padding(.horizontal, count > 99 ? 4 : 0)
                .background(tint, in: .capsule)
                .overlay(Capsule().stroke(.white, lineWidth: 2))
                .shadow(radius: 2)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Zooms in")
    }
}

/// The selected entry: date and time, place, first line, and first photo. Tapping it opens the
/// entry; Open in Maps opens Apple Maps at the spot.
private struct EntryMapCard: View {
    let entry: Entry
    let now: Date

    var body: some View {
        // The card can outlive its entry for a moment after a permanent delete.
        if entry.isAvailable {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: entry) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(entry.topic?.tint ?? .secondary)
                                .frame(width: 8, height: 8)
                            Text(EntryTimeline.dateAndTime(entry.date, now: now))
                                .font(.subheadline.weight(.semibold))
                        }
                        Label(place, systemImage: "location.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let line = TopicMapModel.firstLine(of: entry.body) {
                            Text(line)
                                .font(.subheadline)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 0)
                    if let photo = entry.sortedPhotos.first {
                        PhotoImage(data: photo.thumbnailData, cornerRadius: 8)
                            .frame(width: 56, height: 56)
                    }
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .frame(maxHeight: .infinity)
                        .accessibilityHidden(true)
                }
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the entry")

            if let coordinate = entry.coordinate {
                Button("Open in Maps", systemImage: "map") {
                    MapsApp.open(coordinate, name: entry.placeName)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: .rect(cornerRadius: 20))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }

    private var place: String {
        LocationLabel.text(
            placeName: entry.placeName, latitude: entry.latitude ?? 0,
            longitude: entry.longitude ?? 0)
    }
}

extension Entry {
    /// Both coordinates, or `nil` (see `hasLocation`).
    fileprivate var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension MapGroup {
    fileprivate var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

#Preview("Light") {
    TopicMapPreview()
}

#Preview("Dark") {
    TopicMapPreview()
        .preferredColorScheme(.dark)
}

private struct TopicMapPreview: View {
    var body: some View {
        NavigationStack {
            if let topic = PreviewContainer.topic("Sedona trip") {
                TopicMapView(topic: topic)
            }
        }
        .sampleData()
    }
}
