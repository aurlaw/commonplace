import Foundation

extension Topic {
    /// Entries that are not individually in Trash: what the topic shows, and what comes back
    /// with it when it is restored. Whether the topic itself is trashed is a separate question
    /// (see `Entry.isLive`).
    var liveEntries: [Entry] {
        (entries ?? []).filter { !$0.isTrashed }
    }

    /// Date of the newest entry that is not in Trash.
    var lastEntryDate: Date? {
        liveEntries.map(\.date).max()
    }

    /// Most recent activity first; topics without entries fall back to their creation date.
    static func sortedByRecentActivity(_ topics: [Topic]) -> [Topic] {
        topics.sorted {
            ($0.lastEntryDate ?? $0.createdAt) > ($1.lastEntryDate ?? $1.createdAt)
        }
    }

    /// By title, case- and number-aware; equal titles keep creation order.
    static func sortedByName(_ topics: [Topic]) -> [Topic] {
        topics.sorted {
            switch $0.title.localizedStandardCompare($1.title) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: $0.createdAt < $1.createdAt
            }
        }
    }
}

extension Entry {
    /// Live all the way up: not in Trash, and not inside a trashed topic. Anything that shows
    /// entries outside Trash must only show live ones.
    var isLive: Bool {
        !isTrashed && !(topic?.isTrashed ?? false)
    }
}
