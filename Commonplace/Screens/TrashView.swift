import SwiftData
import SwiftUI

/// Trashed topics and entries, with both actions visible on every item. All actions are inert
/// in the shell.
struct TrashView: View {
    @Query(
        filter: #Predicate<Topic> { $0.deletedAt != nil }, sort: \Topic.deletedAt, order: .reverse)
    private var topics: [Topic]
    @Query(
        filter: #Predicate<Entry> { $0.deletedAt != nil }, sort: \Entry.deletedAt, order: .reverse)
    private var entries: [Entry]

    @Environment(\.referenceDate) private var referenceDate

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
                    Text("Items in Trash still use your iCloud storage until they’re deleted.")
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
                Button("Empty Trash", role: .destructive) {}
                    .tint(.red)
                    .disabled(isEmpty)
            }
        }
    }

    private var isEmpty: Bool {
        topics.isEmpty && entries.isEmpty
    }

    private func topicRow(_ topic: Topic) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(topic.tint)
                .frame(width: 4, height: 34)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(topic.title)
                Text(
                    "\(EntryTimeline.entryCount(topic.liveEntries.count)) · \(deletedLabel(topic.deletedAt))"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                TrashActions()
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
                TrashActions()
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
    var body: some View {
        HStack(spacing: 8) {
            Button("Restore", systemImage: "arrow.uturn.backward") {}
            Button("Delete Permanently", role: .destructive) {}
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
