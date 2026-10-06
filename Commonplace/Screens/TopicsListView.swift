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
    @State private var searchText = ""
    @State private var isArchivedExpanded = false
    @State private var composerMode: ComposerMode?
    @State private var topicEditorMode: TopicEditorMode?

    var body: some View {
        List {
            Section {
                ForEach(activeTopics) { topic in
                    NavigationLink(value: topic) {
                        TopicRow(topic: topic)
                    }
                }
            }
            if !archivedTopics.isEmpty {
                Section {
                    if isArchivedExpanded {
                        ForEach(archivedTopics) { topic in
                            NavigationLink(value: topic) {
                                TopicRow(topic: topic)
                            }
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
            }
        }
        .sheet(item: $composerMode) { mode in
            EntryComposerView(mode: mode, now: referenceDate ?? .now)
        }
        .sheet(item: $topicEditorMode) { mode in
            TopicEditorView(mode: mode)
        }
    }

    private var activeTopics: [Topic] {
        Topic.sortedByRecentActivity(topics.filter { !$0.isArchived })
    }

    private var archivedTopics: [Topic] {
        Topic.sortedByRecentActivity(topics.filter(\.isArchived))
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
                Text(archivedTopics.count, format: .number)
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
        .accessibilityLabel("Archived, \(archivedTopics.count)")
        .accessibilityValue(isArchivedExpanded ? "Expanded" : "Collapsed")
    }

    private var overflowMenu: some View {
        Menu {
            Menu {
                // Inert in the shell: I2 makes the sort order real.
                Picker("Sort By", selection: .constant(TopicSort.recentActivity)) {
                    ForEach(TopicSort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
            } label: {
                Label("Sort By", systemImage: "arrow.up.arrow.down")
                Text(TopicSort.recentActivity.title)
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
}

enum TopicSort: String, CaseIterable, Identifiable {
    case recentActivity
    case name

    var id: Self { self }

    var title: String {
        switch self {
        case .recentActivity: "Recent Activity"
        case .name: "Name"
        }
    }
}
