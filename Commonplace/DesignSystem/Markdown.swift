import Foundation

/// The Markdown subset entries are stored in: `**bold**`, `*italic*`, `- ` / `* ` bulleted
/// lists, `[text](url)`, and bare `http(s)://` URLs. Anything else shows as literal text.
///
/// Blocks are split here; inline syntax is parsed by `AttributedString(markdown:)` with
/// inline-only parsing. Nothing is ever dropped: a block that fails to parse is shown as its
/// literal text.
nonisolated enum MarkdownBody {
    enum Block: Equatable {
        /// Consecutive non-bullet lines, inner blank lines kept.
        case paragraph(String)
        /// The items' text, without their `- ` or `* `.
        case bulletList([String])
    }

    /// Only these schemes are tappable.
    static let allowedSchemes: Set<String> = ["http", "https", "mailto"]

    // MARK: Blocks

    /// Paragraphs and bullet lists, in order. Blank lines around a block separate it from its
    /// neighbors; blank lines inside a paragraph are kept, so plain entries render as before.
    static func blocks(_ body: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [Substring] = []
        var bullets: [String] = []

        func flushParagraph() {
            while paragraph.first?.allSatisfy(\.isWhitespace) == true {
                paragraph.removeFirst()
            }
            while paragraph.last?.allSatisfy(\.isWhitespace) == true {
                paragraph.removeLast()
            }
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            }
            paragraph = []
        }
        func flushBullets() {
            if !bullets.isEmpty {
                blocks.append(.bulletList(bullets))
            }
            bullets = []
        }

        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            if let item = bulletItem(line) {
                flushParagraph()
                bullets.append(item)
            } else {
                flushBullets()
                paragraph.append(line)
            }
        }
        flushParagraph()
        flushBullets()
        return blocks
    }

    /// The text of a bullet line (`- item` or `* item`), or `nil` for any other line.
    static func bulletItem<S: StringProtocol>(_ line: S) -> String? {
        guard line.hasPrefix("- ") || line.hasPrefix("* ") else {
            return nil
        }
        return String(line.dropFirst(2))
    }

    // MARK: Inline

    /// A block's text with bold, italic, and links applied. Bare http(s) URLs become links;
    /// links with other schemes than `allowedSchemes` are plain text. Falls back to the
    /// literal text if parsing fails.
    static func inline(_ text: String) -> AttributedString {
        var attributed: AttributedString
        do {
            attributed = try AttributedString(
                markdown: escapingUnsupported(text),
                options: AttributedString.MarkdownParsingOptions(
                    allowsExtendedAttributes: false,
                    interpretedSyntax: .inlineOnlyPreservingWhitespace,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            )
        } catch {
            return AttributedString(text)
        }
        // Only bold, italic, and links are supported.
        for run in attributed.runs {
            if let intent = run.inlinePresentationIntent {
                let kept = intent.intersection([.emphasized, .stronglyEmphasized])
                attributed[run.range].inlinePresentationIntent = kept.isEmpty ? nil : kept
            }
            if let url = run.link, !isAllowed(url) || isAutolinkedEmail(url, run, in: attributed) {
                attributed[run.range].link = nil
            }
        }
        linkBareURLs(in: &attributed)
        return attributed
    }

    /// The plain text a reader sees: no syntax, link text kept, bullets one per line. This is
    /// what `SearchableText.plain(_:)` returns.
    static func plainText(_ body: String) -> String {
        guard mayContainMarkup(body) else {
            return body
        }
        return blocks(body).map { block in
            switch block {
            case .paragraph(let text):
                String(inline(text).characters)
            case .bulletList(let items):
                items.map { String(inline($0).characters) }.joined(separator: "\n")
            }
        }
        .joined(separator: "\n")
    }

    /// Unique http(s) links in reading order, from Markdown links and bare URLs.
    static func links(in body: String) -> [URL] {
        var seen: Set<String> = []
        var urls: [URL] = []
        for block in blocks(body) {
            let texts: [String] =
                switch block {
                case .paragraph(let text): [text]
                case .bulletList(let items): items
                }
            for text in texts {
                for run in inline(text).runs {
                    guard let url = run.link,
                        let scheme = url.scheme?.lowercased(),
                        scheme == "http" || scheme == "https",
                        seen.insert(url.absoluteString).inserted
                    else {
                        continue
                    }
                    urls.append(url)
                }
            }
        }
        return urls
    }

    // MARK: Helpers

    /// The parser links bare email addresses itself; only bare http(s) URLs are linked.
    /// A `[text](mailto:…)` link is kept.
    private static func isAutolinkedEmail(
        _ url: URL, _ run: AttributedString.Runs.Run, in attributed: AttributedString
    ) -> Bool {
        url.scheme?.lowercased() == "mailto"
            && url.absoluteString == "mailto:" + String(attributed[run.range].characters)
    }

    static func isAllowed(_ url: URL) -> Bool {
        url.scheme.map { allowedSchemes.contains($0.lowercased()) } ?? false
    }

    /// A cheap check that lets plain entries skip parsing entirely.
    private static func mayContainMarkup(_ body: String) -> Bool {
        body.contains { "*[]\\".contains($0) }
            || body.split(separator: "\n").contains { bulletItem($0) != nil }
    }

    /// Escapes the inline syntax the subset doesn't support (code, strikethrough, underscore
    /// emphasis, HTML and autolinks, entities), so it shows literally. Bare URLs are linked
    /// separately.
    private static func escapingUnsupported(_ text: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.count)
        for character in text {
            if "`~_<&".contains(character) {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped
    }

    private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// Adds links to http(s) URLs written out in the text, leaving Markdown links alone. The
    /// parser autolinks most of these already; this covers any it misses.
    private static func linkBareURLs(in attributed: inout AttributedString) {
        let string = String(attributed.characters)
        guard let detector, string.contains("://") else {
            return
        }
        let matches = detector.matches(
            in: string, range: NSRange(string.startIndex..., in: string))
        for match in matches {
            guard let url = match.url,
                let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                let stringRange = Range(match.range, in: string),
                string[stringRange].lowercased().hasPrefix(scheme + "://"),
                let range = Range(stringRange, in: attributed),
                !attributed[range].runs.contains(where: { $0.link != nil })
            else {
                continue
            }
            attributed[range].link = url
        }
    }
}
