import Foundation

extension Topic {
    /// Entries that are not in Trash.
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
}
