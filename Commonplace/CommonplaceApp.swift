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
    /// `nil` in shell mode and under tests, where nothing should geocode or outlive a sheet.
    private let locationCapture: LocationCapture?

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
                    .environment(\.locationCapture, locationCapture)
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
