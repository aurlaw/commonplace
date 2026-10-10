import SwiftData
import SwiftUI

/// The launch screen: live topics, a collapsed Archived section, search and "+ Entry" in the
/// bottom toolbar. Previewed through `RootView`, which owns the navigation stack.
struct TopicsListView: View {
    @Binding var path: NavigationPath

    @Query(filter: #Predicate<Topic> { $0.deletedAt == nil })
    private var topics: [Topic]
    @Query(filter: #Predicate<Topic> { $0.deletedAt != nil })
    private var trashedTopics: [Topic]
    @Query(filter: #Predicate<Entry> { $0.deletedAt != nil })
    private var trashedEntries: [Entry]

    @Environment(\.referenceDate) private var referenceDate
    @Environment(\.modelContext) private var modelContext
    /// A per-device preference, not synced. Stored by raw value.
    @AppStorage("topicSort") private var storedSort = TopicSort.recentActivity.rawValue
    @State private var saveError: String?
    @State private var searchText = ""
    @State private var isArchivedExpanded = false
    @State private var composerMode: ComposerMode?
    @State private var topicEditorMode: TopicEditorMode?

    var body: some View {
        List {
            Section {
                if sections.live.isEmpty {
                    emptyState
                }
                ForEach(sections.live) { topic in
                    topicLink(topic)
                }
            }
            if !sections.archived.isEmpty {
                Section {
                    if isArchivedExpanded {
                        ForEach(sections.archived) { topic in
                            topicLink(topic)
                        }
                    }
                } header: {
                    archivedHeader
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Commonplace")
        .searchable(text: $searchText, prompt: "Search all entries")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("New Topic", systemImage: "rectangle.stack.badge.plus") {
                    topicEditorMode = .new
                }
                .tint(.accentColor)
                overflowMenu
                    .tint(.accentColor)
            }
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button {
                    composerMode = .newFromList
                } label: {
                    Label("Entry", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.glassProminent)
                .accessibilityLabel("New Entry")
                // An entry needs a live topic to go into.
                .disabled(sections.live.isEmpty)
            }
        }
        .sheet(item: $composerMode) { mode in
            EntryComposerView(mode: mode, now: referenceDate ?? .now)
        }
        .sheet(item: $topicEditorMode) { mode in
            TopicEditorView(mode: mode)
        }
        .saveErrorAlert($saveError)
    }

    private var sort: TopicSort {
        TopicSort(storedValue: storedSort)
    }

    private var sections: TopicListSections {
        TopicListSections(topics: topics, sort: sort)
    }

    /// A row with the leading swipe that archives or unarchives and the trailing swipe that
    /// moves the topic to Trash, in both sections.
    private func topicLink(_ topic: Topic) -> some View {
        NavigationLink(value: topic) {
            TopicRow(topic: topic)
        }
        .swipeActions(edge: .leading) {
            Button(
                topic.isArchived ? "Unarchive" : "Archive",
                systemImage: topic.isArchived ? "tray.and.arrow.up" : "archivebox"
            ) {
                withAnimation {
                    topic.isArchived.toggle()
                    saveError = modelContext.saveOrRollback()
                }
            }
        }
        .swipeActions(edge: .trailing) {
            // No confirmation: Trash is the undo.
            Button("Move to Trash", systemImage: "trash", role: .destructive) {
                withAnimation {
                    saveError = TrashOperations(context: modelContext).moveToTrash(topic)
                }
            }
        }
    }

    /// Shown in place of the live topics, above the Archived section when there is one.
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Topics", systemImage: "rectangle.stack")
        } description: {
            Text("Create a topic to start logging entries.")
        } actions: {
            Button("New Topic") {
                topicEditorMode = .new
            }
            .buttonStyle(.borderedProminent)
        }
        .listRowBackground(Color.clear)
    }

    private var trashCount: Int {
        trashedTopics.count + trashedEntries.count
    }

    private var archivedHeader: some View {
        Button {
            withAnimation {
                isArchivedExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Text("Archived")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text(sections.archived.count, format: .number)
                    .font(.subheadline)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .rotationEffect(.degrees(isArchivedExpanded ? 90 : 0))
            }
            .foregroundStyle(.secondary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .textCase(nil)
        .accessibilityLabel("Archived, \(sections.archived.count)")
        .accessibilityValue(isArchivedExpanded ? "Expanded" : "Collapsed")
    }

    private var overflowMenu: some View {
        Menu {
            Menu {
                Picker("Sort By", selection: sortBinding) {
                    ForEach(TopicSort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
            } label: {
                Label("Sort By", systemImage: "arrow.up.arrow.down")
                Text(sort.title)
            }
            Divider()
            Button {
                path.append(AppRoute.trash)
            } label: {
                Label("Trash", systemImage: "trash")
                if trashCount > 0 {
                    Text(trashCount == 1 ? "1 item" : "\(trashCount) items")
                }
            }
            Button("Settings", systemImage: "gearshape") {
                path.append(AppRoute.settings)
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
    }

    private var sortBinding: Binding<TopicSort> {
        Binding(
            get: { sort },
            set: { storedSort = $0.rawValue }
        )
    }
}

/// How the topics list is ordered. Applies to both the live and Archived sections.
enum TopicSort: String, CaseIterable, Identifiable {
    case recentActivity
    case name

    var id: Self { self }

    /// A stored raw value, falling back to Recent Activity when it isn't recognized.
    init(storedValue: String) {
        self = TopicSort(rawValue: storedValue) ?? .recentActivity
    }

    func sorted(_ topics: [Topic]) -> [Topic] {
        switch self {
        case .recentActivity: Topic.sortedByRecentActivity(topics)
        case .name: Topic.sortedByName(topics)
        }
    }

    var title: String {
        switch self {
        case .recentActivity: "Recent Activity"
        case .name: "Name"
        }
    }
}

/// The topics list's two sections, each in the chosen order.
struct TopicListSections {
    /// Not archived.
    let live: [Topic]
    let archived: [Topic]

    /// - Parameter topics: Topics that are not in Trash.
    init(topics: [Topic], sort: TopicSort) {
        live = sort.sorted(topics.filter { !$0.isArchived })
        archived = sort.sorted(topics.filter(\.isArchived))
    }
}
