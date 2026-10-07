import Foundation
import SwiftData

extension SchemaV1 {
    @Model
    final class Entry {
        /// User-editable; drives timeline order.
        var date: Date = Date.now
        var createdAt: Date = Date.now
        var body: String = ""
        var deletedAt: Date? = nil
        /// Set together with `longitude`: an entry has both coordinates or neither.
        var latitude: Double? = nil
        var longitude: Double? = nil
        /// Can be `nil` while a location exists: captured offline, geocoded later.
        var placeName: String? = nil
        var topic: Topic? = nil

        @Relationship(deleteRule: .cascade, inverse: \Photo.entry)
        var photos: [Photo]? = []

        init(
            body: String = "",
            date: Date = .now,
            topic: Topic? = nil,
            createdAt: Date = .now
        ) {
            self.body = body
            self.date = date
            self.topic = topic
            self.createdAt = createdAt
        }

        var isTrashed: Bool { deletedAt != nil }

        /// True only when both coordinates are set.
        var hasLocation: Bool { latitude != nil && longitude != nil }

        /// CloudKit-backed relationships are unordered, so order is explicit.
        var sortedPhotos: [Photo] {
            (photos ?? []).sorted { lhs, rhs in
                if lhs.order != rhs.order {
                    return lhs.order < rhs.order
                }
                return lhs.createdAt < rhs.createdAt
            }
        }
    }
}
