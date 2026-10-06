import SwiftUI

/// Destinations that aren't a model value.
enum AppRoute: Hashable {
    case trash
    case settings
}

/// The app's single navigation stack: Topics → Topic → Entry, plus Trash and Settings.
struct RootView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            TopicsListView(path: $path)
                .navigationDestination(for: Topic.self) { topic in
                    TopicDetailView(topic: topic)
                }
                .navigationDestination(for: Entry.self) { entry in
                    EntryDetailView(entry: entry)
                }
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .trash: TrashView()
                    case .settings: SettingsView()
                    }
                }
        }
    }
}

#Preview("Light") {
    RootView()
        .sampleData()
}

#Preview("Dark") {
    RootView()
        .sampleData()
        .preferredColorScheme(.dark)
}
