import SwiftData
import SwiftUI

/// The seeded in-memory container every `#Preview` uses.
enum PreviewContainer {
    static let shared: ModelContainer = {
        do {
            return try SampleData.makeContainer()
        } catch {
            fatalError("Could not create the preview container: \(error)")
        }
    }()

    /// A seeded topic by title.
    static func topic(_ title: String) -> Topic? {
        let descriptor = FetchDescriptor<Topic>(predicate: #Predicate { $0.title == title })
        return try? shared.mainContext.fetch(descriptor).first
    }

    /// A seeded, non-trashed entry by position in its topic, oldest first.
    static func entry(in topicTitle: String, at index: Int) -> Entry? {
        let entries = (topic(topicTitle)?.liveEntries ?? []).sorted { $0.date < $1.date }
        return entries.indices.contains(index) ? entries[index] : nil
    }
}

extension View {
    /// Attaches the seeded container, the seed's fixed "now", and a fake location service, so
    /// previews never ask for location access or geocode.
    func sampleData(location: FakeLocationService = FakeLocationService()) -> some View {
        modelContainer(PreviewContainer.shared)
            .environment(\.referenceDate, SampleData.now)
            .environment(\.locationService, location)
    }
}
