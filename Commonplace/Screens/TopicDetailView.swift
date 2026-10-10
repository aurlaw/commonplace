import SwiftData
import SwiftUI

/// A topic's timeline: tinted header, then entries grouped by month, newest first.
struct TopicDetailView: View {
    let topic: Topic

    @Environment(\.referenceDate) private var referenceDate
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    /// An entry waiting for its Delete Permanently confirmation.
    @State private var entryPendingDelete: Entry?
    @State private var composerMode: ComposerMode?
    @State private var topicEditorMode: TopicEditorMode?
    @State private var isConfirmingDelete: Bool
    @State private var saveError: String?

    init(topic: Topic, isConfirmingDelete: Bool = false) {
        self.topic = topic
        _isConfirmingDelete = State(initialValue: isConfirmingDelete)
    }

    var body: some View {
        // The screen outlives its topic for a moment after a permanent delete.
        if topic.isAvailable {
            content
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TopicHeader(topic: topic)
                if sections.isEmpty {
                    ContentUnavailableView(
                        "No Entries",
                        systemImage: "square.and.pencil",
                        description: Text("Entries you add to this topic appear here.")
                    )
                    .padding(.top, 48)
                }
                ForEach(sections) { section in
                    Text(section.title())
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 4)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(section.entries) { entry in
                        NavigationLink(value: entry) {
                            EntryRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                        // The timeline isn't a List, so there is no swipe: a long press instead.
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") {
                                composerMode = .edit(entry)
                            }
                            Divider()
                            Button("Move to Trash", systemImage: "trash") {
                                saveError = trash.moveToTrash(entry)
                            }
                            Button(
                                "Delete Permanently", systemImage: "trash.slash",
                                role: .destructive
                            ) {
                                entryPendingDelete = entry
                            }
                        }
                        Divider()
                            .padding(.leading, 64)
                    }
                }
            }
        }
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                overflowMenu
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                // The one control filled with the topic color: adds straight to this topic.
                Button("New Entry", systemImage: "plus") {
                    composerMode = .newInTopic(topic)
                }
                .buttonStyle(.glassProminent)
                .tint(topic.tint)
            }
        }
        .sheet(item: $composerMode) { mode in
            EntryComposerView(mode: mode, now: referenceDate ?? .now)
        }
        .sheet(item: $topicEditorMode) { mode in
            TopicEditorView(mode: mode)
        }
        .alert(deleteTitle, isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive) {
                leave(after: trash.deletePermanently(topic))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can’t be undone.")
        }
        .deleteEntryAlert($entryPendingDelete) { entry in
            saveError = trash.deletePermanently(entry)
        }
        .saveErrorAlert($saveError)
    }

    private var sections: [EntryTimeline.MonthSection] {
        EntryTimeline.groupByMonth(topic.liveEntries)
    }

    private var trash: TrashOperations {
        TrashOperations(context: modelContext)
    }

    /// Returns to the topics list once the topic is gone, or shows why it isn't.
    private func leave(after error: String?) {
        if let error {
            saveError = error
        } else {
            dismiss()
        }
    }

    /// Counts every entry the delete removes, including ones already in Trash.
    private var deleteTitle: String {
        let count = EntryTimeline.entryCount(TrashOperations.entriesDeleted(with: topic))
        return "Delete “\(topic.title)” and its \(count)?"
    }

    private var overflowMenu: some View {
        Menu {
            Button("Edit Topic", systemImage: "pencil") {
                topicEditorMode = .edit(topic)
            }
            Divider()
            Button(
                topic.isArchived ? "Unarchive Topic" : "Archive Topic",
                systemImage: topic.isArchived ? "tray.and.arrow.up" : "archivebox"
            ) {
                topic.isArchived.toggle()
                saveError = modelContext.saveOrRollback()
            }
            Button("Move to Trash", systemImage: "trash") {
                leave(after: trash.moveToTrash(topic))
            }
            Button("Delete Permanently", systemImage: "trash.slash", role: .destructive) {
                isConfirmingDelete = true
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
    }
}

#Preview("Light") {
    TopicDetailPreview()
}

#Preview("Dark") {
    TopicDetailPreview()
        .preferredColorScheme(.dark)
}

#Preview("Delete confirmation") {
    TopicDetailPreview(isConfirmingDelete: true)
}

#Preview("Delete confirmation · Dark") {
    TopicDetailPreview(isConfirmingDelete: true)
        .preferredColorScheme(.dark)
}

private struct TopicDetailPreview: View {
    var isConfirmingDelete = false

    var body: some View {
        NavigationStack {
            if let topic = PreviewContainer.topic("Sedona trip") {
                TopicDetailView(topic: topic, isConfirmingDelete: isConfirmingDelete)
            }
        }
        .sampleData()
    }
}
