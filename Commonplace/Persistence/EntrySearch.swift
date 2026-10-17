import Foundation
import SwiftData

/// Runs a search against the store. The fetch is narrowed in SQL by the first word; the full
/// rules (every word, live only, order, cap) are applied in memory by `SearchResults`.
struct EntrySearch {
    let context: ModelContext

    func results(for query: SearchQuery) throws -> SearchResults {
        guard query.isSearchable, let first = query.tokens.first else {
            return SearchResults(query: query, topics: [], entries: [])
        }
        let topics = try context.fetch(Self.liveTopics)
        let entries = try context.fetch(Self.candidates(matching: first))
        return SearchResults(query: query, topics: topics, entries: entries)
    }

    private static var liveTopics: FetchDescriptor<Topic> {
        FetchDescriptor(predicate: #Predicate { $0.deletedAt == nil })
    }

    /// Entries not individually trashed whose text or place name contains `token`. The place
    /// name is part of the narrowing so a match found only there isn't filtered out.
    static func candidates(matching token: String) -> FetchDescriptor<Entry> {
        let predicate = #Predicate<Entry> { entry in
            entry.deletedAt == nil
                && (entry.body.localizedStandardContains(token)
                    || entry.placeName?.localizedStandardContains(token) == true)
        }
        return FetchDescriptor(predicate: predicate)
    }
}
