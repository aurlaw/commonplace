import SwiftData
import SwiftUI

/// Destinations that aren't a model value.
enum AppRoute: Hashable {
    case trash
    case settings
}

/// The app's single navigation stack: Topics → Topic → Entry, plus Trash and Settings.
struct RootView: View {
    @Environment(\.locationCapture) private var locationCapture
    @Environment(\.scenePhase) private var scenePhase
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
        // On launch and each return to the foreground: name places that were saved offline.
        // Geocoding needs no location permission, so nothing is asked for here.
        .task(id: scenePhase) {
            if scenePhase == .active {
                await locationCapture?.backfillPlaceNames()
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

// The one preview without the seed: a fresh install has no topics.
#Preview("Empty") {
    if let container = try? ModelContainerFactory.makeInMemory() {
        RootView()
            .modelContainer(container)
    }
}
