import MapKit
import SwiftUI
import UniformTypeIdentifiers

/// Confirms a picked GPX file before it is attached: the route's name, date, stats, and line,
/// and — when the entry has no location — whether to use the route's start as one. Nothing is
/// saved until Save; Cancel discards the draft.
struct RouteAttachSheet: View {
    let draft: RouteDraft
    let entry: Entry
    /// Called on Save with the location toggle's value.
    let onSave: (_ useStartAsLocation: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var useStartAsLocation = false
    @State private var segments: [[Coordinate]] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    preview
                        .listRowInsets(EdgeInsets())
                }
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(draft.name)
                                .font(.headline)
                            if let recorded = draft.startedAt {
                                Text("Recorded \(EntryTimeline.fullDate(recorded))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        RouteStatsRow(stats: draft.stats)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        RouteAttachText.spokenSummary(
                            name: draft.name, recorded: draft.startedAt, stats: draft.stats))
                } footer: {
                    if let note = RouteAttachText.dateNote(
                        recorded: draft.startedAt, entryDate: entry.date)
                    {
                        Text(note)
                    }
                }
                if offersLocation {
                    Section {
                        Toggle("Use route start as entry location", isOn: $useStartAsLocation)
                    } footer: {
                        Text(
                            "This entry has no location. The place name is looked up when you’re online."
                        )
                    }
                }
            }
            .navigationTitle(entry.hasRoute ? "Replace Route" : "Add Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", role: .confirm) {
                        onSave(offersLocation && useStartAsLocation)
                        dismiss()
                    }
                }
            }
            .task {
                segments = await RoutePathDecoder.coordinates(from: draft.pathData)
            }
        }
    }

    /// Only an entry without a location is offered one; an existing location is never replaced.
    private var offersLocation: Bool {
        !entry.hasLocation && draft.startCoordinate != nil
    }

    private var preview: some View {
        let pin = entry.locationCoordinate
        return Map(
            initialPosition: RouteCamera.region(segments: segments, pin: pin).map { .region($0) }
                ?? .automatic,
            interactionModes: []
        ) {
            RoutePolylines(segments: segments, tint: entry.topic?.tint ?? .accentColor)
            if let pin {
                Marker("Entry", coordinate: pin.clLocation)
                    .tint(entry.topic?.tint ?? .accentColor)
            }
        }
        .id(segments.reduce(0) { $0 + $1.count })
        .frame(height: 200)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// "Couldn’t Add Route" with the reason (`GPXError.message`, or the read error).
    func routeErrorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "Couldn’t Add Route",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

extension UTType {
    /// GPX, as declared under Imported Type Identifiers in the target's Info. Without that
    /// declaration (or another app's), falls back to the type for the `gpx` extension.
    static let gpx =
        UTType("com.topografix.gpx") ?? UTType(filenameExtension: "gpx", conformingTo: .xml)
        ?? .xml
}

/// Reading a file the Files picker handed over.
nonisolated enum RouteFile {
    /// The file's contents, read off the main actor inside its security scope. Files over the
    /// size limit are refused before reading.
    @concurrent
    static func read(_ url: URL) async throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
            size > RouteLimits.maxFileBytes
        {
            throw GPXError.tooLarge
        }
        return try Data(contentsOf: url)
    }
}

// MARK: - Previews

#Preview("Location toggle") {
    AttachPreview(topic: "Stoic practice", index: 4)
}

#Preview("Location toggle · Dark") {
    AttachPreview(topic: "Stoic practice", index: 4)
        .preferredColorScheme(.dark)
}

#Preview("Has location") {
    AttachPreview(topic: "Sedona trip", index: 2)
}

#Preview("Date mismatch") {
    // Devil's Bridge, Oct 3, with the Oct 2 Cathedral Rock track.
    AttachPreview(topic: "Sedona trip", index: 3)
}

#Preview("Date mismatch · Dark") {
    AttachPreview(topic: "Sedona trip", index: 3)
        .preferredColorScheme(.dark)
}

#Preview("Parse error") {
    Color.clear
        .routeErrorAlert(.constant(GPXError.noTrack.message))
}

#Preview("Parse error · Dark") {
    Color.clear
        .routeErrorAlert(.constant(GPXError.notGPX.message))
        .preferredColorScheme(.dark)
}

private struct AttachPreview: View {
    let topic: String
    let index: Int

    var body: some View {
        if let entry = PreviewContainer.entry(in: topic, at: index),
            let draft = SampleRoutes.draft(SampleRoutes.cathedralRock)
        {
            RouteAttachSheet(draft: draft, entry: entry) { _ in }
                .sampleData()
        }
    }
}
