import SwiftUI

/// A topic's timeline: tinted header, then entries grouped by month, newest first.
struct TopicDetailView: View {
    let topic: Topic

    @Environment(\.referenceDate) private var referenceDate
    @State private var composerMode: ComposerMode?
    @State private var topicEditorMode: TopicEditorMode?
    @State private var isConfirmingDelete: Bool

    init(topic: Topic, isConfirmingDelete: Bool = false) {
        self.topic = topic
        _isConfirmingDelete = State(initialValue: isConfirmingDelete)
    }

    var body: some View {
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
            // Inert in the shell: both buttons only dismiss.
            Button("Delete", role: .destructive) {}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can’t be undone.")
        }
    }

    private var sections: [EntryTimeline.MonthSection] {
        EntryTimeline.groupByMonth(topic.liveEntries)
    }

    private var deleteTitle: String {
        let count = EntryTimeline.entryCount(topic.liveEntries.count)
        return "Delete “\(topic.title)” and its \(count)?"
    }

    private var overflowMenu: some View {
        Menu {
            Button("Edit Topic", systemImage: "pencil") {
                topicEditorMode = .edit(topic)
            }
            Divider()
            Button("Move to Trash", systemImage: "trash") {}
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
