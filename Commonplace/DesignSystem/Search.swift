import Foundation

/// The one place entry text becomes plain text: search matching and snippets, timeline and
/// Trash rows. Markdown syntax is stripped, link text kept, and bullets flattened to lines.
nonisolated enum SearchableText {
    static func plain(_ body: String) -> String {
        MarkdownBody.plainText(body)
    }
}

nonisolated enum SearchRule {
    /// How long typing must pause before a search runs.
    static let debounce = Duration.milliseconds(250)
}

/// A search as typed: whitespace-separated words, every one of which must match.
nonisolated struct SearchQuery: Equatable {
    /// Searching starts at this many characters, ignoring surrounding whitespace.
    static let minimumLength = 2

    /// Trimmed of surrounding punctuation; punctuation-only words are dropped.
    let tokens: [String]
    private let trimmedLength: Int

    init(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        trimmedLength = trimmed.count
        tokens =
            trimmed
            .split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: .punctuationCharacters.union(.symbols)) }
            .filter { !$0.isEmpty }
    }

    /// Long enough to search, with at least one word.
    var isSearchable: Bool {
        trimmedLength >= Self.minimumLength && !tokens.isEmpty
    }

    /// Whether every token is found in at least one of `texts`, in any order. Case- and
    /// diacritic-insensitive (`localizedStandardContains`).
    func matches(_ texts: [String]) -> Bool {
        guard !tokens.isEmpty else {
            return false
        }
        return tokens.allSatisfy { token in
            texts.contains { $0.localizedStandardContains(token) }
        }
    }

    func matches(_ text: String) -> Bool {
        matches([text])
    }

    /// Where any token occurs in `text`, in order, without overlaps.
    func matchRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        for token in tokens {
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                let range = text.range(
                    of: token, options: Self.options, range: searchStart..<text.endIndex,
                    locale: .current)
            {
                ranges.append(range)
                searchStart = range.upperBound
            }
        }
        ranges.sort { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for range in ranges {
            if let last = merged.last, range.lowerBound < last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    /// The same comparison as `localizedStandardContains`.
    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
}

/// A short excerpt of an entry around its first match, with the matched words marked.
nonisolated struct SearchSnippet: Equatable {
    /// How much text comes before the first match.
    static let leadingContext = 40
    /// Roughly two lines in a result row.
    static let maximumLength = 140

    /// One line of text: line breaks and runs of whitespace become single spaces. Starts with
    /// "…" when text before the match was cut.
    let text: String
    let highlights: [Range<String.Index>]
    /// Present only when the match is (also) in the place name.
    let placeName: String?
    let placeNameHighlights: [Range<String.Index>]

    init(body: String, placeName: String?, query: SearchQuery) {
        let flat = Self.flatten(SearchableText.plain(body))
        let firstMatch = query.matchRanges(in: flat).first
        let excerpt = Self.excerpt(of: flat, around: firstMatch)
        text = excerpt
        highlights = query.matchRanges(in: excerpt)

        if let placeName, !query.matchRanges(in: placeName).isEmpty {
            self.placeName = placeName
            placeNameHighlights = query.matchRanges(in: placeName)
        } else {
            self.placeName = nil
            placeNameHighlights = []
        }
    }

    private static func flatten(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// From a little before the match (at a word boundary) to about two lines on. Without a
    /// match (it's in the place name), from the start.
    private static func excerpt(of text: String, around match: Range<String.Index>?) -> String {
        var start = text.startIndex
        var isTrimmedAtStart = false
        if let match,
            text.distance(from: text.startIndex, to: match.lowerBound) > leadingContext
        {
            let earliest = text.index(match.lowerBound, offsetBy: -leadingContext)
            // Begin at the next word, so the excerpt doesn't open mid-word.
            if let space = text[earliest..<match.lowerBound].firstIndex(of: " ") {
                start = text.index(after: space)
            } else {
                start = match.lowerBound
            }
            isTrimmedAtStart = true
        }
        var end = text.endIndex
        var isTrimmedAtEnd = false
        if text.distance(from: start, to: text.endIndex) > maximumLength {
            let latest = text.index(start, offsetBy: maximumLength)
            // End at a word boundary, but never before the match.
            let floor = match.map { max($0.upperBound, start) } ?? start
            if floor < latest, let space = text[floor..<latest].lastIndex(of: " ") {
                end = space
            } else {
                end = latest
            }
            isTrimmedAtEnd = true
        }
        return (isTrimmedAtStart ? "…" : "") + text[start..<end] + (isTrimmedAtEnd ? "…" : "")
    }
}

/// Search results across the journal, in display order.
struct SearchResults {
    /// Entries beyond this many are left out, with a note.
    static let entryLimit = 100

    /// Live topics whose title matches, by recent activity. Archived ones included.
    let topics: [Topic]
    /// Live entries whose text or place name matches, newest first, at most `entryLimit`.
    let entries: [Entry]
    /// Whether more entries matched than are shown.
    let isCapped: Bool

    /// - Parameters:
    ///   - topics: Candidate topics; trashed ones are dropped.
    ///   - entries: Candidate entries; ones that aren't live are dropped.
    init(query: SearchQuery, topics: [Topic], entries: [Entry]) {
        guard query.isSearchable else {
            self.topics = []
            self.entries = []
            isCapped = false
            return
        }
        self.topics = Topic.sortedByRecentActivity(
            topics.filter { !$0.isTrashed && query.matches($0.title) }
        )
        let matching =
            entries
            .filter { $0.isLive && Self.matches($0, query) }
            .sorted(by: Self.isNewer)
        self.entries = Array(matching.prefix(Self.entryLimit))
        isCapped = matching.count > Self.entryLimit
    }

    var isEmpty: Bool {
        topics.isEmpty && entries.isEmpty
    }

    /// The counts, for VoiceOver: "2 topics, 24 entries".
    var announcement: String {
        guard !isEmpty else {
            return "No results"
        }
        var parts: [String] = []
        if !topics.isEmpty {
            parts.append(topics.count == 1 ? "1 topic" : "\(topics.count) topics")
        }
        if !entries.isEmpty {
            parts.append(EntryTimeline.entryCount(entries.count))
        }
        return parts.joined(separator: ", ")
    }

    /// Every token must be in the entry's text or its place name, in any combination.
    static func matches(_ entry: Entry, _ query: SearchQuery) -> Bool {
        query.matches([SearchableText.plain(entry.body), entry.placeName ?? ""])
    }

    /// Newest first by date; entries at the same time, most recently created first.
    private static func isNewer(_ lhs: Entry, _ rhs: Entry) -> Bool {
        if lhs.date != rhs.date {
            return lhs.date > rhs.date
        }
        return lhs.createdAt > rhs.createdAt
    }
}
