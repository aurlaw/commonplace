import Foundation
import SwiftData

/// How long trashed items are kept before the auto-purge. A per-device preference, not synced.
nonisolated enum TrashRetention: String, CaseIterable, Identifiable, Sendable {
    case thirtyDays
    case ninetyDays
    case never

    /// `@AppStorage` key for the raw value.
    static let storageKey = "trashRetention"
    /// `@AppStorage` key for when the auto-purge last ran, as seconds since the reference date.
    static let lastPurgeKey = "lastTrashPurge"
    static let defaultValue = TrashRetention.thirtyDays

    var id: Self { self }

    /// A stored raw value, falling back to the default when it isn't recognized.
    init(storedValue: String) {
        self = TrashRetention(rawValue: storedValue) ?? .defaultValue
    }

    var title: String {
        switch self {
        case .thirtyDays: "30 days"
        case .ninetyDays: "90 days"
        case .never: "Never"
        }
    }

    /// `nil` for Never.
    var days: Int? {
        switch self {
        case .thirtyDays: 30
        case .ninetyDays: 90
        case .never: nil
        }
    }

    /// Items trashed at or before this moment have been kept long enough. `nil` for Never.
    func cutoff(before now: Date) -> Date? {
        days.map { now.addingTimeInterval(-Double($0) * 86_400) }
    }

    /// Whether a change from `self` to `newValue` keeps items for less time.
    func isShortened(by newValue: TrashRetention) -> Bool {
        (newValue.days ?? .max) < (days ?? .max)
    }

    /// What the Trash footer says about this setting.
    var footer: String {
        if let days {
            "Items are deleted automatically after \(days) days."
        } else {
            "Items are kept until you delete them."
        }
    }

    /// The auto-purge runs at most once a day.
    static func isPurgeDue(lastPurge: Date?, now: Date) -> Bool {
        guard let lastPurge else {
            return true
        }
        return now.timeIntervalSince(lastPurge) >= 86_400
    }
}

/// Every way an item enters or leaves Trash. Each operation saves, and returns the error
/// message to show with `.saveErrorAlert(_:)`, or `nil` on success.
///
/// Apart from removing a photo in the composer, this is the only place `modelContext.delete`
/// is called.
struct TrashOperations {
    let context: ModelContext
    /// The clock. Tests replace it to control time.
    var now: () -> Date = { .now }

    // MARK: Move to Trash and restore

    /// Stamps the topic only. Its entries keep their own state and are hidden because the
    /// topic is trashed.
    func moveToTrash(_ topic: Topic) -> String? {
        topic.deletedAt = now()
        return context.saveOrRollback()
    }

    func moveToTrash(_ entry: Entry) -> String? {
        entry.deletedAt = now()
        return context.saveOrRollback()
    }

    /// Brings back the topic and the entries that were live when it was trashed. Entries
    /// trashed individually stay in Trash; the archived state is unchanged.
    func restore(_ topic: Topic) -> String? {
        topic.deletedAt = nil
        return context.saveOrRollback()
    }

    /// Brings back the entry, and its topic too when the topic is in Trash, since an entry
    /// can't be live inside a trashed topic. The view asks before calling this in that case.
    func restore(_ entry: Entry) -> String? {
        entry.deletedAt = nil
        if let topic = entry.topic, topic.isTrashed {
            topic.deletedAt = nil
        }
        return context.saveOrRollback()
    }

    // MARK: Permanent delete

    /// Deletes the topic with every entry in it, trashed or not, and their photos.
    func deletePermanently(_ topic: Topic) -> String? {
        context.delete(topic)
        return context.saveOrRollback()
    }

    /// Deletes the entry and its photos.
    func deletePermanently(_ entry: Entry) -> String? {
        context.delete(entry)
        return context.saveOrRollback()
    }

    func emptyTrash() -> String? {
        delete(trashedTopics(), trashedEntries())
    }

    /// Deletes what has been in Trash for the retention period or longer. Does nothing for
    /// Never.
    func purge(retention: TrashRetention) -> String? {
        guard let cutoff = retention.cutoff(before: now()) else {
            return nil
        }
        return delete(
            trashedTopics().filter { Self.isExpired($0.deletedAt, cutoff: cutoff) },
            trashedEntries().filter { Self.isExpired($0.deletedAt, cutoff: cutoff) }
        )
    }

    // MARK: Counts for confirmations

    /// Entries a permanent delete of the topic removes: all of them, including ones already
    /// in Trash.
    static func entriesDeleted(with topic: Topic) -> Int {
        (topic.entries ?? []).count
    }

    /// Items Empty Trash removes, as Trash lists them: trashed topics plus individually
    /// trashed entries.
    func emptyTrashCount() -> Int {
        trashedTopics().count + trashedEntries().count
    }

    /// Items a purge with this retention would remove now, counted as Trash lists them.
    func purgeCount(retention: TrashRetention) -> Int {
        guard let cutoff = retention.cutoff(before: now()) else {
            return 0
        }
        return trashedTopics().filter { Self.isExpired($0.deletedAt, cutoff: cutoff) }.count
            + trashedEntries().filter { Self.isExpired($0.deletedAt, cutoff: cutoff) }.count
    }

    // MARK: Internals

    private static func isExpired(_ deletedAt: Date?, cutoff: Date) -> Bool {
        deletedAt.map { $0 <= cutoff } ?? false
    }

    private func trashedTopics() -> [Topic] {
        (try? context.fetch(FetchDescriptor<Topic>(predicate: #Predicate { $0.deletedAt != nil })))
            ?? []
    }

    private func trashedEntries() -> [Entry] {
        (try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.deletedAt != nil })))
            ?? []
    }

    /// Deletes topics first; their entries go with them through the cascade, so those are
    /// skipped in the entry pass.
    private func delete(_ topics: [Topic], _ entries: [Entry]) -> String? {
        let doomedTopics = Set(topics.map(\.persistentModelID))
        for entry in entries {
            if let topicID = entry.topic?.persistentModelID, doomedTopics.contains(topicID) {
                continue
            }
            context.delete(entry)
        }
        for topic in topics {
            context.delete(topic)
        }
        return context.saveOrRollback()
    }
}
