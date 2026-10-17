//
//  CommonplaceApp.swift
//  Commonplace
//
//  Created by Michael Lawrence on 10/5/26.
//

import SwiftData
import SwiftUI

@main
struct CommonplaceApp: App {
    private let container: Result<ModelContainer, any Error>
    private let locationService: any LocationService
    private let transcriptionService: any TranscriptionService
    /// One instance, so the session's cache and failed URLs are shared.
    private let linkMetadataService: any LinkMetadataService
    private let textCleaner: any TextCleaner
    /// `nil` in shell mode and under tests, where nothing should geocode or outlive a sheet.
    private let locationCapture: LocationCapture?
    /// Under tests and in shell mode, a lock that can never engage, with its own settings.
    @State private var appLock: AppLock

    init() {
        container = Result {
            if Self.isRunningTests {
                // Unit tests are hosted in the app; they must never create the CloudKit store.
                return try ModelContainerFactory.makeInMemory()
            }
            if AppConfig.usesSampleData {
                return try SampleData.makeContainer()
            }
            return try ModelContainerFactory.makePersistent()
        }
        let usesRealStore = !Self.isRunningTests && !AppConfig.usesSampleData
        locationService = usesRealStore ? CoreLocationService() : FakeLocationService()
        transcriptionService =
            usesRealStore ? SpeechTranscriptionService() : FakeTranscriptionService()
        _appLock = State(
            initialValue: usesRealStore
                ? AppLock(authenticator: LocalAuthenticator())
                : AppLock(
                    defaults: UserDefaults(suiteName: "appLock.inert") ?? .standard,
                    authenticator: FakeBiometricAuthenticator(availability: .unavailable)
                )
        )
        linkMetadataService =
            usesRealStore ? CachedLinkMetadataService() : FakeLinkMetadataService()
        textCleaner = usesRealStore ? FoundationModelsCleaner() : FakeTextCleaner()
        if usesRealStore, case .success(let container) = container {
            locationCapture = LocationCapture(
                service: locationService, context: container.mainContext
            )
        } else {
            locationCapture = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            switch container {
            case .success(let container):
                RootView()
                    .modelContainer(container)
                    .environment(\.referenceDate, Self.usesSampleData ? SampleData.now : nil)
                    .environment(\.locationService, locationService)
                    .environment(\.transcriptionService, transcriptionService)
                    .environment(\.linkMetadataService, linkMetadataService)
                    .environment(\.textCleaner, textCleaner)
                    .environment(\.locationCapture, locationCapture)
                    .appLock(appLock)
            case .failure(let error):
                ContainerErrorView(message: error.localizedDescription)
            }
        }
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Whether the running app is showing the seed (shell mode).
    private static var usesSampleData: Bool {
        AppConfig.usesSampleData && !isRunningTests
    }
}
