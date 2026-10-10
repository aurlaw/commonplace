import Accessibility
import SwiftData
import SwiftUI

/// A reader for a whole topic: the tapped entry in full, with its neighbors a swipe away.
///
/// Paging happens in place. The navigation stack keeps the entry that was tapped, so Back and
/// the topic chip always return to the topic, however far you've paged.
struct EntryDetailView: View {
    /// The entry that was tapped: where the reader opens.
    let entry: Entry

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.referenceDate) private var referenceDate
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The entry currently shown. The toolbar, Edit, and the photo viewer all act on it.
    @State private var current: Entry
    /// Kept from the tapped entry, which may itself be deleted while the reader is open.
    @State private var topic: Topic?
    @State private var entryPendingDelete: Entry?
    @State private var saveError: String?
    /// Set once the reader has asked to close, so it doesn't ask twice.
    @State private var isLeaving = false
    @State private var position: ScrollPosition
    @State private var isScrolling = false
    /// The bars' insets. The horizontal scroll view doesn't pass them down to its pages.
    @State private var barInsets = EdgeInsets()
    @State private var composerMode: ComposerMode?
    @State private var viewerSelection: PhotoSelection?

    init(entry: Entry) {
        self.entry = entry
        _current = State(initialValue: entry)
        _topic = State(initialValue: entry.topic)
        // Starting on the tapped entry as initial state means there is no scroll to animate.
        var position = ScrollPosition(idType: PersistentIdentifier.self)
        position.scrollTo(id: entry.persistentModelID)
        _position = State(initialValue: position)
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(entries) { entry in
                    EntryPage(entry: entry, barInsets: barInsets) { index in
                        viewerSelection = PhotoSelection(entry: entry, index: index)
                    }
                    .containerRelativeFrame([.horizontal, .vertical])
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition($position)
        .scrollIndicators(.hidden)
        .onGeometryChange(for: EdgeInsets.self) { proxy in
            proxy.safeAreaInsets
        } action: { insets in
            barInsets = insets
        }
        .onScrollPhaseChange { _, newPhase in
            isScrolling = newPhase != .idle
            if newPhase == .idle {
                adoptScrolledEntry()
            }
        }
        .onChange(of: position.viewID(type: PersistentIdentifier.self)) {
            // Only a scroll moves the reader. When the order changes underneath it, the scroll
            // view may report a different entry at the same offset; `keepPlace` handles that.
            if isScrolling {
                adoptScrolledEntry()
            }
        }
        .onChange(of: entries.map(\.persistentModelID)) {
            keepPlace()
        }
        .onChange(of: neighbors?.positionLabel) { _, label in
            if let label {
                AccessibilityNotification.Announcement(label).post()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                // The topic chip is the way home.
                Button {
                    dismiss()
                } label: {
                    TopicChip(topic: topic, dotSize: 9)
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
        .deleteEntryAlert($entryPendingDelete) { entry in
            remove(entry, permanently: true)
        }
        .saveErrorAlert($saveError)
        .fullScreenCover(item: $viewerSelection) { selection in
            PhotoViewer(
                photos: selection.entry.sortedPhotos,
                startIndex: selection.index,
                caption: EntryTimeline.monthDay(selection.entry.date) + " · "
                    + EntryTimeline.time(selection.entry.date)
            )
        }
    }

    /// The topic's live entries, oldest on the left and newest on the right.
    private var entries: [Entry] {
        EntryTimeline.readingOrder(topic?.liveEntries ?? [current].filter(\.isAvailable))
    }

    private var neighbors: EntryTimeline.Neighbors? {
        EntryTimeline.neighbors(of: current, in: entries)
    }

    // MARK: Paging

    /// Makes the entry the scroll view has settled on, or is passing, the current one.
    private func adoptScrolledEntry() {
        guard let id = position.viewID(type: PersistentIdentifier.self),
            let scrolled = entries.first(where: { $0.persistentModelID == id })
        else {
            return
        }
        if scrolled !== current {
            current = scrolled
        }
    }

    /// Moves to a neighbor from the bottom bar. No animation with Reduce Motion on.
    private func page(to target: Entry) {
        current = target
        withAnimation(reduceMotion ? nil : .default) {
            position.scrollTo(id: target.persistentModelID)
        }
    }

    /// Called when the topic's entries change (an edit that re-dates, an import, a trashed
    /// entry). Stays on the current entry, or falls back when it is no longer live.
    private func keepPlace() {
        guard !isLeaving else {
            return
        }
        if !entries.contains(where: { $0 === current }) {
            // A deleted entry can't be read, so there is no "nearest": take the newest.
            let replacement =
                current.isAvailable
                ? EntryTimeline.replacement(for: current, in: entries) : entries.last
            guard let replacement else {
                leave()
                return
            }
            current = replacement
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            position.scrollTo(id: current.persistentModelID)
        }
    }

    /// Trashes or deletes an entry, then moves to its neighbor, or back to the topic when it
    /// was the last one. The neighbor is worked out first, while the entry can still be read.
    private func remove(_ entry: Entry, permanently: Bool) {
        let replacement = EntryTimeline.replacement(for: entry, in: entries)
        let trash = TrashOperations(context: modelContext)
        let error = permanently ? trash.deletePermanently(entry) : trash.moveToTrash(entry)
        if let error {
            saveError = error
        } else if let replacement {
            current = replacement
        } else {
            leave()
        }
    }

    /// Back to the topic, once.
    private func leave() {
        guard !isLeaving else {
            return
        }
        isLeaving = true
        dismiss()
    }

    // MARK: Toolbar

    /// Tap targets for the neighboring entries, and the accessible way to page.
    @ToolbarContentBuilder private var neighborBar: some ToolbarContent {
        if let neighbors {
            if let previous = neighbors.previous {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        page(to: previous)
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
                        page(to: next)
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
                composerMode = .edit(current)
            }
            Divider()
            Button("Move to Trash", systemImage: "trash") {
                remove(current, permanently: false)
            }
            Button("Delete Permanently", systemImage: "trash.slash", role: .destructive) {
                entryPendingDelete = current
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
    }
}

/// One entry in full: date, time, body, and photos, scrolling vertically.
private struct EntryPage: View {
    let entry: Entry
    /// Space taken by the navigation bar and bottom bar.
    let barInsets: EdgeInsets
    let onSelectPhoto: (Int) -> Void

    var body: some View {
        // A page can outlive its entry for a moment after a permanent delete.
        if entry.isAvailable {
            content
        }
    }

    private var content: some View {
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
                    PhotoGrid(photos: entry.sortedPhotos, onSelect: onSelectPhoto)
                }
                if entry.hasLocation {
                    EntryLocationView(entry: entry)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        // Content starts below the navigation bar and ends above the bottom bar, and still
        // scrolls beneath both.
        .contentMargins(.top, barInsets.top, for: .scrollContent)
        .contentMargins(.bottom, barInsets.bottom, for: .scrollContent)
        .contentMargins(.top, barInsets.top, for: .scrollIndicators)
        .contentMargins(.bottom, barInsets.bottom, for: .scrollIndicators)
    }
}

private struct PhotoSelection: Identifiable {
    let entry: Entry
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

#Preview("No location") {
    EntryDetailPreview(topic: "Stoic practice", index: 4)
}

#Preview("No location · Dark") {
    EntryDetailPreview(topic: "Stoic practice", index: 4)
        .preferredColorScheme(.dark)
}

private struct EntryDetailPreview: View {
    var topic = "Sedona trip"
    var index = 2

    var body: some View {
        NavigationStack {
            if let entry = PreviewContainer.entry(in: topic, at: index) {
                EntryDetailView(entry: entry)
            }
        }
        .sampleData()
    }
}
