import SwiftUI

nonisolated extension TopicColor {
    /// The system colors carry the design's exact light and dark values.
    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .brown: .brown
        case .green: .green
        case .teal: .teal
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        }
    }
}

extension Topic {
    /// The topic's color as a SwiftUI `Color`.
    var tint: Color {
        color.color
    }
}
