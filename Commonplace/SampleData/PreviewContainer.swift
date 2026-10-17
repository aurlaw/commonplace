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

    /// Unlocked, with Face ID available and its own settings, so previews never lock.
    static let appLock = AppLock(
        defaults: UserDefaults(suiteName: "preview.appLock") ?? .standard,
        authenticator: FakeBiometricAuthenticator()
    )

    /// Locked, for the lock screen's previews.
    static let lockedAppLock: AppLock = {
        let defaults = UserDefaults(suiteName: "preview.appLock.locked") ?? .standard
        defaults.set(true, forKey: AppLock.enabledKey)
        return AppLock(
            defaults: defaults,
            authenticator: FakeBiometricAuthenticator(result: .cancelled)
        )
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
    /// Attaches the seeded container, the seed's fixed "now", and fake location and
    /// transcription services, so previews never ask for location or microphone access,
    /// geocode, or listen.
    func sampleData(
        location: FakeLocationService = FakeLocationService(),
        transcription: FakeTranscriptionService = FakeTranscriptionService(),
        links: FakeLinkMetadataService = FakeLinkMetadataService(),
        cleaner: FakeTextCleaner = FakeTextCleaner()
    ) -> some View {
        modelContainer(PreviewContainer.shared)
            .environment(\.referenceDate, SampleData.now)
            .environment(\.locationService, location)
            .environment(\.transcriptionService, transcription)
            .environment(PreviewContainer.appLock)
            .environment(\.linkMetadataService, links)
            .environment(\.textCleaner, cleaner)
    }
}
