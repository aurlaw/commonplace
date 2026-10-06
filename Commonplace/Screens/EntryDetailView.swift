import SwiftUI

/// One entry in full: date, body, photos, and a bottom bar naming its neighbors by date.
struct EntryDetailView: View {
    let entry: Entry

    @Environment(\.dismiss) private var dismiss
    @Environment(\.referenceDate) private var referenceDate
    @State private var composerMode: ComposerMode?
    @State private var viewerSelection: PhotoSelection?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(EntryTimeline.fullDate(entry.date))
                        .font(.title2.bold())
                    Text(EntryTimeline.time(entry.date))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(entry.body)
                    .lineSpacing(3)
                if !entry.sortedPhotos.isEmpty {
                    PhotoGrid(photos: entry.sortedPhotos) { index in
                        viewerSelection = PhotoSelection(index: index)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                // The topic chip is the way home.
                Button {
                    dismiss()
                } label: {
                    TopicChip(topic: entry.topic, dotSize: 9)
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glass)
                .accessibilityHint("Back to topic")
            }
            ToolbarItem(placement: .topBarTrailing) {
                overflowMenu
            }
            neighborBar
        }
        .sheet(item: $composerMode) { mode in
            EntryComposerView(mode: mode, now: referenceDate ?? .now)
        }
        .fullScreenCover(item: $viewerSelection) { selection in
            PhotoViewer(
                photos: entry.sortedPhotos,
                startIndex: selection.index,
                caption: "\(EntryTimeline.monthDay(entry.date)) · \(EntryTimeline.time(entry.date))"
            )
        }
    }

    private var neighbors: EntryTimeline.Neighbors? {
        EntryTimeline.neighbors(of: entry, in: entry.topic?.liveEntries ?? [entry])
    }

    /// Visible tap targets for the neighboring entries. Inert in the shell: paging is I4.
    @ToolbarContentBuilder private var neighborBar: some ToolbarContent {
        if let neighbors {
            if let previous = neighbors.previous {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text(EntryTimeline.monthDay(previous.date))
                        }
                    }
                    .accessibilityLabel("Previous entry, \(EntryTimeline.monthDay(previous.date))")
                }
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Text(neighbors.positionLabel)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarSpacer(.flexible, placement: .bottomBar)
            if let next = neighbors.next {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                    } label: {
                        HStack(spacing: 4) {
                            Text(EntryTimeline.monthDay(next.date))
                            Image(systemName: "chevron.right")
                        }
                    }
                    .accessibilityLabel("Next entry, \(EntryTimeline.monthDay(next.date))")
                }
            }
        }
    }

    private var overflowMenu: some View {
        Menu {
            Button("Edit", systemImage: "pencil") {
                composerMode = .edit(entry)
            }
            Divider()
            Button("Move to Trash", systemImage: "trash") {}
            Button("Delete Permanently", systemImage: "trash.slash", role: .destructive) {}
        } label: {
            Label("More", systemImage: "ellipsis")
        }
    }
}

private struct PhotoSelection: Identifiable {
    let index: Int

    var id: Int { index }
}

#Preview("Light") {
    EntryDetailPreview()
}

#Preview("Dark") {
    EntryDetailPreview()
        .preferredColorScheme(.dark)
}

private struct EntryDetailPreview: View {
    var body: some View {
        NavigationStack {
            if let entry = PreviewContainer.entry(in: "Sedona trip", at: 2) {
                EntryDetailView(entry: entry)
            }
        }
        .sampleData()
    }
}
