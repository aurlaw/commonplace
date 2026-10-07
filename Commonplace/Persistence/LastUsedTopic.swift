import Foundation
import SwiftData

/// The topic "+ Entry" on the topics list opens on: the one the last new entry was saved to.
///
/// A per-device preference, not synced. The view keeps the encoded value in
/// `@AppStorage(LastUsedTopic.storageKey)`; the rules live here.
nonisolated enum LastUsedTopic {
    static let storageKey = "lastUsedTopic"

    /// The topic's persistent identifier as JSON, or `nil` if it can't be encoded.
    static func encode(_ topic: Topic) -> Data? {
        try? JSONEncoder().encode(topic.persistentModelID)
    }

    static func decode(_ data: Data) -> PersistentIdentifier? {
        try? JSONDecoder().decode(PersistentIdentifier.self, from: data)
    }

    /// The stored topic when it still exists, isn't in Trash, and isn't archived; otherwise the
    /// first usable topic by recent activity. `nil` only when no topic is usable.
    static func resolve(stored: Data?, among topics: [Topic]) -> Topic? {
        let usable = topics.filter { !$0.isTrashed && !$0.isArchived }
        if let stored, let identifier = decode(stored),
            let topic = usable.first(where: { $0.persistentModelID == identifier })
        {
            return topic
        }
        return Topic.sortedByRecentActivity(usable).first
    }
}
