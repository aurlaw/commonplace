import SwiftData
import SwiftUI

/// Trashed topics and individually trashed entries, newest first, with both actions visible on
/// every item. Rows aren't tappable: trashed items are restored or deleted, not opened.
struct TrashView: View {
    @Query(
        filter: #Predicate<Topic> { $0.deletedAt != nil }, sort: \Topic.deletedAt, order: .reverse)
    private var topics: [Topic]
    @Query(
        filter: #Predicate<Entry> { $0.deletedAt != nil }, sort: \Entry.deletedAt, order: .reverse)
    private var entries: [Entry]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.referenceDate) private var referenceDate
    @AppStorage(TrashRetention.storageKey) private var storedRetention =
        TrashRetention.defaultValue.rawValue
    @State private var topicPendingDelete: Topic?
    @State private var entryPendingDelete: Entry?
    /// An entry whose topic is also in Trash, waiting for the "restore both" confirmation.
    @State private var entryPendingRestore: Entry?
    @State private var isConfirmingEmpty = false
    @State private var saveError: String?

    var body: some View {
        List {
            if !topics.isEmpty {
                Section {
                    ForEach(topics) { topic in
                        topicRow(topic)
                    }
                } header: {
                    Text("Topics").textCase(nil)
                }
            }
            if !entries.isEmpty {
                Section {
                    ForEach(entries) { entry in
                        entryRow(entry)
                    }
                } header: {
                    Text("Entries").textCase(nil)
                }
            }
            if !isEmpty {
                Section {
                } footer: {
                    Text(
                        "Items in Trash still use your iCloud storage until they’re deleted. "
                            + TrashRetention(storedValue: storedRetention).footer
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if isEmpty {
                ContentUnavailableView("Trash Is Empty", systemImage: "trash")
            }
        }
        .navigationTitle("Trash")
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button("Empty Trash", role: .destructive) {
                    isConfirmingEmpty = true
                }
                .tint(.red)
                .disabled(isEmpty)
            }
        }
        .alert(emptyTitle, isPresented: $isConfirmingEmpty) {
            Button("Delete", role: .destructive) {
                saveError = trash.emptyTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Everything in Trash will be deleted. This can’t be undone.")
        }
        .alert(
            deleteTopicTitle,
            isPresented: isPresenting($topicPendingDelete),
            presenting: topicPendingDelete
        ) { topic in
            Button("Delete", role: .destructive) {
                saveError = trash.deletePermanently(topic)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This can’t be undone.")
        }
        .deleteEntryAlert($entryPendingDelete) { entry in
            saveError = trash.deletePermanently(entry)
        }
        .alert(
            restoreBothTitle,
            isPresented: isPresenting($entryPendingRestore),
            presenting: entryPendingRestore
        ) { entry in
            Button("Restore Both") {
                saveError = trash.restore(entry)
            }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            Text(restoreBothMessage(for: entry))
        }
        .saveErrorAlert($saveError)
    }

    private var isEmpty: Bool {
        topics.isEmpty && entries.isEmpty
    }

    private var trash: TrashOperations {
        TrashOperations(context: modelContext)
    }

    // MARK: Actions

    /// Restores at once when the entry's topic is live. When the topic is in Trash too, asks
    /// first, because the topic and its other entries come back with it.
    private func restore(_ entry: Entry) {
        if entry.topic?.isTrashed == true {
            entryPendingRestore = entry
        } else {
            saveError = trash.restore(entry)
        }
    }

    // MARK: Confirmation copy

    private var emptyTitle: String {
        let count = topics.count + entries.count
        return count == 1 ? "Delete 1 Item Permanently?" : "Delete \(count) Items Permanently?"
    }

    /// Counts every entry the delete removes, including ones trashed individually.
    private var deleteTopicTitle: String {
        // The alert can outlive the topic it just deleted for a moment.
        guard let topic = topicPendingDelete, topic.isAvailable else {
            return ""
        }
        let count = EntryTimeline.entryCount(TrashOperations.entriesDeleted(with: topic))
        return "Delete “\(topic.title)” and its \(count)?"
    }

    private var restoreBothTitle: String {
        "Restore “\(entryPendingRestore?.topic?.title ?? "")” too?"
    }

    private func restoreBothMessage(for entry: Entry) -> String {
        // The topic's own live entries, plus this one.
        let count = EntryTimeline.entryCount((entry.topic?.liveEntries.count ?? 0) + 1)
        return "This entry’s topic is in Trash. Restoring the entry also restores the topic "
            + "and its \(count)."
    }

    private func isPresenting<Item>(_ item: Binding<Item?>) -> Binding<Bool> {
        Binding(
            get: { item.wrappedValue != nil },
            set: { isPresented in
                if !isPresented {
                    item.wrappedValue = nil
                }
            }
        )
    }

    // MARK: Rows

    private func topicRow(_ topic: Topic) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(topic.tint)
                .frame(width: 4, height: 34)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(topic.title)
                // The entries that come back with the topic.
                Text(
                    "\(EntryTimeline.entryCount(topic.liveEntries.count)) · \(deletedLabel(topic.deletedAt))"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                TrashActions {
                    saveError = trash.restore(topic)
                } onDelete: {
                    topicPendingDelete = topic
                }
                .padding(.top, 8)
            }
        }
    }

    private func entryRow(_ entry: Entry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    TopicChip(topic: entry.topic)
                    Text("· \(deletedLabel(entry.deletedAt))")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                Text(entry.body)
                    .font(.subheadline)
                    .lineLimit(2)
                TrashActions {
                    restore(entry)
                } onDelete: {
                    entryPendingDelete = entry
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
            if let photo = entry.sortedPhotos.first {
                PhotoImage(data: photo.thumbnailData, cornerRadius: 9)
                    .frame(width: 52, height: 52)
            }
        }
    }

    /// "Deleted Sep 19"
    private func deletedLabel(_ date: Date?) -> String {
        guard let date else {
            return "Deleted"
        }
        return "Deleted \(EntryTimeline.shortDate(date, now: referenceDate ?? .now))"
    }
}

/// Restore and Delete Permanently, visible on every item rather than hidden behind swipes.
private struct TrashActions: View {
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button("Restore", systemImage: "arrow.uturn.backward", action: onRestore)
            Button("Delete Permanently", role: .destructive, action: onDelete)
                .tint(.red)
        }
        .font(.subheadline.weight(.semibold))
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
    }
}

#Preview("Light") {
    TrashPreview()
}

#Preview("Dark") {
    TrashPreview()
        .preferredColorScheme(.dark)
}

private struct TrashPreview: View {
    var body: some View {
        NavigationStack {
            TrashView()
        }
        .sampleData()
    }
}
