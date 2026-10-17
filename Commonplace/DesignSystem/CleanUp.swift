import Foundation

/// The text of an entry cut into pieces for Clean Up: chunks the model may edit, and the
/// separators between them, kept exactly. Joining every piece in order gives back the
/// original text.
nonisolated enum CleanUpChunks {
    enum Piece: Equatable {
        case chunk(String)
        /// Line breaks, blank lines, or the space between sentences. Never sent to the model.
        case separator(String)

        var text: String {
            switch self {
            case .chunk(let text), .separator(let text): text
            }
        }
    }

    /// About 1,000 tokens at a conservative ~3 characters a token, for when the token-count
    /// API isn't available.
    static let defaultBudget = 3_000

    /// One chunk per paragraph or bullet list (I11a's blocks), split at blank lines and where
    /// bullets start or stop. A chunk over `budget` characters is split at sentences.
    static func split(_ text: String, budget: Int = defaultBudget) -> [Piece] {
        // Each chunk's range in `text`: a run of non-blank lines, all bullets or all not.
        var ranges: [Range<String.Index>] = []
        var current: Range<String.Index>?
        var currentIsBullets = false
        var lineStart = text.startIndex
        while lineStart <= text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[lineStart..<lineEnd]
            if line.allSatisfy(\.isWhitespace) {
                if let range = current {
                    ranges.append(range)
                    current = nil
                }
            } else {
                let isBullet = MarkdownBody.bulletItem(line) != nil
                if let range = current, isBullet == currentIsBullets {
                    current = range.lowerBound..<lineEnd
                } else {
                    if let range = current {
                        ranges.append(range)
                    }
                    current = lineStart..<lineEnd
                    currentIsBullets = isBullet
                }
            }
            guard lineEnd < text.endIndex else {
                break
            }
            lineStart = text.index(after: lineEnd)
        }
        if let range = current {
            ranges.append(range)
        }

        // Separators are exactly the text between chunks.
        var pieces: [Piece] = []
        var position = text.startIndex
        for range in ranges {
            if position < range.lowerBound {
                pieces.append(.separator(String(text[position..<range.lowerBound])))
            }
            pieces += splitOversized(String(text[range]), budget: budget)
            position = range.upperBound
        }
        if position < text.endIndex {
            pieces.append(.separator(String(text[position...])))
        }
        return pieces
    }

    /// Splits a chunk over `budget` at sentence boundaries, packing sentences up to the
    /// budget. A single sentence over it is split at a space.
    static func splitOversized(_ text: String, budget: Int) -> [Piece] {
        guard text.count > budget else {
            return [.chunk(text)]
        }
        var sentences: [Substring] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) {
            _, _, enclosing, _ in
            // The enclosing range includes the whitespace after the sentence.
            sentences.append(text[enclosing])
        }
        if sentences.isEmpty {
            sentences = [text[...]]
        }
        var pieces: [Piece] = []
        var current = ""
        func flush() {
            guard !current.isEmpty else {
                return
            }
            // Trailing whitespace goes to a separator, so chunks start and end with words.
            let trimmed = current.trimmingTrailingWhitespace()
            pieces.append(.chunk(trimmed))
            let trailing = String(current.dropFirst(trimmed.count))
            if !trailing.isEmpty {
                pieces.append(.separator(trailing))
            }
            current = ""
        }
        for sentence in sentences {
            if !current.isEmpty, current.count + sentence.count > budget {
                flush()
            }
            if sentence.count > budget {
                for part in hardSplit(String(sentence), budget: budget) {
                    current = part
                    flush()
                }
            } else {
                current += sentence
            }
        }
        flush()
        return pieces
    }

    /// Splits at the last space before each `budget` characters.
    private static func hardSplit(_ text: String, budget: Int) -> [String] {
        var parts: [String] = []
        var rest = Substring(text)
        while rest.count > budget {
            let limit = rest.index(rest.startIndex, offsetBy: budget)
            let cut = rest[..<limit].lastIndex(of: " ").map { rest.index(after: $0) } ?? limit
            parts.append(String(rest[..<cut]))
            rest = rest[cut...]
        }
        if !rest.isEmpty {
            parts.append(String(rest))
        }
        return parts
    }

    static func join(_ pieces: [Piece]) -> String {
        pieces.map(\.text).joined()
    }
}

/// The safety post-check on a cleaned chunk. Anything it rejects keeps the original text.
nonisolated enum CleanUpCheck {
    /// The cleaned length, as a share of the original's, outside of which the result reads as
    /// a summary or an addition.
    static let lengthRange = 0.5...1.3

    static func accepts(original: String, cleaned: String) -> Bool {
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !original.isEmpty else {
            return false
        }
        let ratio = Double(trimmed.count) / Double(original.count)
        guard lengthRange.contains(ratio) else {
            return false
        }
        // Every URL, in the same order.
        guard allLinks(in: original) == allLinks(in: trimmed) else {
            return false
        }
        // Markdown stays as written: the same emphasis markers and link brackets.
        for character: Character in ["*", "[", "]"] {
            guard count(character, in: original) == count(character, in: trimmed) else {
                return false
            }
        }
        // Bullet lines stay bullet lines.
        return bulletLines(in: original) == bulletLines(in: trimmed)
    }

    /// Every link destination, in order, duplicates included.
    static func allLinks(in text: String) -> [String] {
        MarkdownBody.blocks(text).flatMap { block -> [String] in
            let texts: [String] =
                switch block {
                case .paragraph(let text): [text]
                case .bulletList(let items): items
                }
            return texts.flatMap { text in
                let attributed = MarkdownBody.inline(text)
                return attributed.runs.compactMap { $0.link?.absoluteString }
            }
        }
    }

    private static func count(_ character: Character, in text: String) -> Int {
        text.reduce(0) { $1 == character ? $0 + 1 : $0 }
    }

    private static func bulletLines(in text: String) -> Int {
        text.split(separator: "\n").filter { MarkdownBody.bulletItem($0) != nil }.count
    }
}

/// What a Clean Up produced.
nonisolated struct CleanUpOutcome: Equatable {
    var text: String
    /// Chunks the model changed and the post-check accepted.
    var cleanedCount: Int
    /// Chunks left as they were because cleaning failed or the post-check rejected it.
    var failedCount: Int

    var changed: Bool {
        cleanedCount > 0
    }

    /// The brief note shown after a clean-up, or `nil` when everything was cleaned.
    var message: String? {
        if !changed {
            return "No changes"
        }
        return failedCount > 0 ? "Some text couldn’t be cleaned up" : nil
    }
}

nonisolated enum CleanUpRule {
    /// A body this long makes Clean Up likely enough to load the model ahead of time.
    static let prewarmLength = 280
}

/// Runs Clean Up over a whole body: splits it, cleans each chunk in order, checks each
/// result, and joins the pieces with the original separators.
nonisolated enum CleanUpRunner {
    static func run(
        _ body: String,
        with cleaner: any TextCleaner,
        budget: Int = CleanUpChunks.defaultBudget
    ) async -> CleanUpOutcome {
        var outcome = CleanUpOutcome(text: "", cleanedCount: 0, failedCount: 0)
        var pieces: [String] = []
        for piece in CleanUpChunks.split(body, budget: budget) {
            guard case .chunk(let original) = piece else {
                pieces.append(piece.text)
                continue
            }
            guard !Task.isCancelled else {
                pieces.append(original)
                continue
            }
            let result = await cleanChunk(original, with: cleaner, budget: budget)
            pieces.append(result.text)
            outcome.cleanedCount += result.cleanedCount
            outcome.failedCount += result.failedCount
        }
        outcome.text = pieces.joined()
        return outcome
    }

    /// One chunk. On a context overflow it is split smaller once and those parts are cleaned;
    /// a second overflow, a refusal, or any other failure keeps the original.
    private static func cleanChunk(
        _ original: String, with cleaner: any TextCleaner, budget: Int, isRetry: Bool = false
    ) async -> CleanUpOutcome {
        do {
            let cleaned = try await cleaner.clean(original)
            let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == original {
                return CleanUpOutcome(text: original, cleanedCount: 0, failedCount: 0)
            }
            guard CleanUpCheck.accepts(original: original, cleaned: trimmed) else {
                return CleanUpOutcome(text: original, cleanedCount: 0, failedCount: 1)
            }
            return CleanUpOutcome(text: trimmed, cleanedCount: 1, failedCount: 0)
        } catch TextCleanerError.contextOverflow where !isRetry {
            // Small enough that the chunk really splits; not so small it splits mid-word.
            let smaller = max(40, min(budget, original.count) / 2)
            var outcome = CleanUpOutcome(text: "", cleanedCount: 0, failedCount: 0)
            for piece in CleanUpChunks.splitOversized(original, budget: smaller) {
                guard case .chunk(let part) = piece else {
                    outcome.text += piece.text
                    continue
                }
                let result = await cleanChunk(part, with: cleaner, budget: smaller, isRetry: true)
                outcome.text += result.text
                outcome.cleanedCount += result.cleanedCount
                outcome.failedCount += result.failedCount
            }
            return outcome
        } catch {
            return CleanUpOutcome(text: original, cleanedCount: 0, failedCount: 1)
        }
    }
}

extension String {
    nonisolated fileprivate func trimmingTrailingWhitespace() -> String {
        var result = self
        while result.last?.isWhitespace == true {
            result.removeLast()
        }
        return result
    }
}
