import Foundation

/// The fixed palette a topic can be tagged with. Persisted as its raw value in `Topic.colorName`.
nonisolated enum TopicColor: String, CaseIterable, Codable, Sendable {
    case blue
    case teal
    case green
    case yellow
    case orange
    case red
    case pink
    case purple

    static let defaultColor: TopicColor = .blue
}
