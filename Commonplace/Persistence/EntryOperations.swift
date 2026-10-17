import Foundation
import SwiftData

/// One-step changes to an entry outside the composer.
struct EntryOperations {
    let context: ModelContext

    /// Moves a live entry to another live topic. Photos and location go with it; the
    /// destination's location setting doesn't add or remove one, and the last-used topic is
    /// unchanged. Saves, and returns the error message on failure (the entry stays put).
    func move(_ entry: Entry, to topic: Topic) -> String? {
        guard entry.isLive, !topic.isTrashed, entry.topic !== topic else {
            return nil
        }
        entry.topic = topic
        return context.saveOrRollback()
    }
}
