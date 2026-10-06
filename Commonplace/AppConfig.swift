import SwiftUI

nonisolated enum AppConfig {
    /// Shell mode (I1b): the app runs on a seeded in-memory container and nothing persists.
    ///
    /// **I2 flips this to `false`**, which switches the app to the persistent CloudKit container.
    static let usesSampleData = true
}

extension EnvironmentValues {
    /// A fixed "now" for relative labels ("Today", "Yesterday"). `nil` means the real clock.
    ///
    /// Set to `SampleData.now` in shell mode and previews so the seeded dates read as designed.
    @Entry var referenceDate: Date? = nil
}
