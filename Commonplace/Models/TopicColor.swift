import Foundation

/// The fixed palette a topic can be tagged with. Persisted as its raw value in `Topic.colorName`.
///
/// Blue is deliberately absent: it is reserved for the system accent.
nonisolated enum TopicColor: String, CaseIterable, Codable, Sendable {
    case red
    case orange
    case brown
    case green
    case teal
    case indigo
    case purple
    case pink

    static let defaultColor: TopicColor = .indigo

    /// For accessibility labels.
    var displayName: String {
        rawValue.capitalized
    }
}
