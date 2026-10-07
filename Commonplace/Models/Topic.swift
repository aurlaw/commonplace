import Foundation
import SwiftData

extension SchemaV1 {
    @Model
    final class Topic {
        var title: String = ""
        var summary: String = ""
        var colorName: String = TopicColor.defaultColor.rawValue
        var isArchived: Bool = false
        /// Whether new entries in this topic capture location by default.
        var capturesLocation: Bool = false
        var createdAt: Date = Date.now
        var deletedAt: Date? = nil

        @Relationship(deleteRule: .cascade, inverse: \Entry.topic)
        var entries: [Entry]? = []

        init(
            title: String = "",
            summary: String = "",
            color: TopicColor = .defaultColor,
            createdAt: Date = .now
        ) {
            self.title = title
            self.summary = summary
            self.colorName = color.rawValue
            self.createdAt = createdAt
        }

        /// Falls back to the default color when `colorName` holds an unknown raw value.
        var color: TopicColor {
            get { TopicColor(rawValue: colorName) ?? .defaultColor }
            set { colorName = newValue.rawValue }
        }

        var isTrashed: Bool { deletedAt != nil }
    }
}
