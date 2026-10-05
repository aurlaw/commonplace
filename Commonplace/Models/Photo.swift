import Foundation
import SwiftData

extension SchemaV1 {
    @Model
    final class Photo {
        @Attribute(.externalStorage)
        var imageData: Data? = nil
        var thumbnailData: Data? = nil
        var order: Int = 0
        var createdAt: Date = Date.now
        var entry: Entry? = nil

        init(
            imageData: Data? = nil,
            thumbnailData: Data? = nil,
            order: Int = 0,
            entry: Entry? = nil,
            createdAt: Date = .now
        ) {
            self.imageData = imageData
            self.thumbnailData = thumbnailData
            self.order = order
            self.entry = entry
            self.createdAt = createdAt
        }
    }
}
