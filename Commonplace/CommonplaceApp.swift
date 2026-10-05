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

    init() {
        container = Result {
            // Unit tests are hosted in the app; they must never create the CloudKit store.
            try Self.isRunningTests
                ? ModelContainerFactory.makeInMemory()
                : ModelContainerFactory.makePersistent()
        }
    }

    var body: some Scene {
        WindowGroup {
            switch container {
            case .success(let container):
                ContentView()
                    .modelContainer(container)
            case .failure(let error):
                ContainerErrorView(message: error.localizedDescription)
            }
        }
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
