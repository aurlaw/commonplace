import SwiftUI

nonisolated enum AppConfig {
    /// Shell mode: when `true` the app runs on a seeded in-memory container and nothing persists.
    ///
    /// Off since I2 — the app uses the persistent CloudKit container. Kept as a switch so the
    /// shell can be turned back on for design work.
    static let usesSampleData = false
}

extension EnvironmentValues {
    /// A fixed "now" for relative labels ("Today", "Yesterday"). `nil` means the real clock.
    ///
    /// Set to `SampleData.now` in shell mode and previews so the seeded dates read as designed.
    @Entry var referenceDate: Date? = nil
}
