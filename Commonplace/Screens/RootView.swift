import OSLog
import SwiftData
import SwiftUI

/// Destinations that aren't a model value on its own.
enum AppRoute: Hashable {
    case trash
    case settings
    /// The topic's located entries on a map.
    case topicMap(Topic)
}

/// The app's single navigation stack: Topics → Topic → Entry, plus Trash and Settings.
struct RootView: View {
    @Environment(\.locationCapture) private var locationCapture
    @Environment(\.modelContext) private var modelContext
    @Environment(\.referenceDate) private var referenceDate
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(TrashRetention.storageKey) private var storedRetention =
        TrashRetention.defaultValue.rawValue
    /// When the auto-purge last ran, as seconds since the reference date. `0` means never.
    @AppStorage(TrashRetention.lastPurgeKey) private var lastPurge = 0.0
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
                    case .topicMap(let topic): TopicMapView(topic: topic)
                    }
                }
        }
        // On launch and each return to the foreground: name places that were saved offline.
        // Geocoding needs no location permission, so nothing is asked for here.
        .task(id: scenePhase) {
            if scenePhase == .active {
                purgeTrashIfDue()
                await locationCapture?.backfillPlaceNames()
            }
        }
    }

    /// Deletes items that have outstayed the retention setting, at most once a day. Failures
    /// are logged, not shown: nothing here was asked for by the user.
    private func purgeTrashIfDue() {
        let now = referenceDate ?? .now
        let last = lastPurge > 0 ? Date(timeIntervalSinceReferenceDate: lastPurge) : nil
        guard TrashRetention.isPurgeDue(lastPurge: last, now: now) else {
            return
        }
        let trash = TrashOperations(context: modelContext, now: { now })
        if let error = trash.purge(retention: TrashRetention(storedValue: storedRetention)) {
            Logger(subsystem: "com.aurlaw.commonplace", category: "trash")
                .error("Trash purge failed: \(error, privacy: .public)")
        } else {
            lastPurge = now.timeIntervalSinceReferenceDate
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
