import Foundation

/// The formatting bar's operations, as pure functions on text and a selection. Offsets are
/// character offsets into the text; the composer converts them to and from `TextSelection`.
nonisolated enum MarkdownEditing {
    struct Edit: Equatable {
        var text: String
        var selection: Range<Int>
    }

    enum Style {
        case bold
        case italic

        var marker: String {
            switch self {
            case .bold: "**"
            case .italic: "*"
            }
        }
    }

    // MARK: Bold and italic

    /// Wraps the selection in `**…**` or `*…*`, or unwraps it if it is already wrapped (inside
    /// the markers, or with them selected). With an empty selection, inserts the pair and puts
    /// the cursor between. Whitespace at the edges of the selection stays outside the markers.
    static func toggle(_ style: Style, in text: String, selection: Range<Int>) -> Edit {
        var characters = Array(text)
        let selection = clamped(selection, to: characters.count)
        let marker = Array(style.marker)
        let length = marker.count

        // The markers are selected along with the text.
        let selected = Array(characters[selection])
        if selected.count >= 2 * length,
            isWrapped(selected, style: style),
            Array(selected.prefix(length)) == marker
        {
            characters.removeSubrange((selection.upperBound - length)..<selection.upperBound)
            characters.removeSubrange(selection.lowerBound..<(selection.lowerBound + length))
            return Edit(
                text: String(characters),
                selection: selection.lowerBound..<(selection.upperBound - 2 * length)
            )
        }

        // The markers are just outside the selection.
        let before = asteriskRun(in: characters, endingAt: selection.lowerBound)
        let after = asteriskRun(in: characters, startingAt: selection.upperBound)
        if !selection.isEmpty, wrapsAround(before: before, after: after, style: style) {
            characters.removeSubrange(selection.upperBound..<(selection.upperBound + length))
            characters.removeSubrange((selection.lowerBound - length)..<selection.lowerBound)
            return Edit(
                text: String(characters),
                selection: (selection.lowerBound - length)..<(selection.upperBound - length)
            )
        }

        // Wrap, keeping edge whitespace outside the markers.
        var lower = selection.lowerBound
        var upper = selection.upperBound
        while lower < upper, characters[lower].isWhitespace {
            lower += 1
        }
        while upper > lower, characters[upper - 1].isWhitespace {
            upper -= 1
        }
        characters.insert(contentsOf: marker, at: upper)
        characters.insert(contentsOf: marker, at: lower)
        return Edit(text: String(characters), selection: (lower + length)..<(upper + length))
    }

    /// Whether a run of asterisks either side carries this style's marker: bold in runs of 2 or
    /// 3, italic in runs of 1 or 3 (`***both***`).
    private static func wrapsAround(before: Int, after: Int, style: Style) -> Bool {
        switch style {
        case .bold: (before == 2 || before == 3) && (after == 2 || after == 3)
        case .italic: before % 2 == 1 && after % 2 == 1 && before <= 3 && after <= 3
        }
    }

    private static func isWrapped(_ selected: [Character], style: Style) -> Bool {
        let leading = selected.prefix { $0 == "*" }.count
        let trailing = selected.reversed().prefix { $0 == "*" }.count
        guard leading < selected.count else {
            return false
        }
        return wrapsAround(before: leading, after: trailing, style: style)
    }

    private static func asteriskRun(in characters: [Character], endingAt index: Int) -> Int {
        var count = 0
        while index - count > 0, characters[index - count - 1] == "*" {
            count += 1
        }
        return count
    }

    private static func asteriskRun(in characters: [Character], startingAt index: Int) -> Int {
        var count = 0
        while index + count < characters.count, characters[index + count] == "*" {
            count += 1
        }
        return count
    }

    // MARK: Bullets

    /// Toggles `- ` at the start of every line the selection touches. If every touched line
    /// is already a bullet, the bullets are removed; otherwise lines without one get one.
    /// Across several lines, blank lines are left alone. The selection covers the same text
    /// afterwards.
    static func toggleBullets(in text: String, selection: Range<Int>) -> Edit {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let selection = clamped(selection, to: text.count)

        // Each line's start offset.
        var starts: [Int] = []
        var offset = 0
        for line in lines {
            starts.append(offset)
            offset += line.count + 1
        }
        func lineIndex(at position: Int) -> Int {
            (starts.lastIndex { $0 <= position }) ?? 0
        }
        let first = lineIndex(at: selection.lowerBound)
        var last = lineIndex(at: selection.upperBound)
        // A selection ending at the very start of a line doesn't touch it.
        if last > first, starts[last] == selection.upperBound {
            last -= 1
        }
        let touched = Array(first...last)
        let candidates =
            touched.count == 1
            ? touched : touched.filter { !lines[$0].allSatisfy(\.isWhitespace) }
        let removing =
            !candidates.isEmpty
            && candidates.allSatisfy { MarkdownBody.bulletItem(lines[$0]) != nil }

        // Line starts (in the old text) where "- " is added or removed.
        var changed: [Int] = []
        for index in candidates {
            if removing {
                lines[index].removeFirst(2)
            } else if MarkdownBody.bulletItem(lines[index]) == nil {
                lines[index] = "- " + lines[index]
            } else {
                continue
            }
            changed.append(starts[index])
        }
        // Moves an old offset to the same text in the new one. A selection that starts at a
        // line start keeps the new bullet inside it; a cursor moves past it.
        func map(_ position: Int, isLowerBound: Bool = false) -> Int {
            var shift = 0
            for start in changed {
                let isAfter =
                    isLowerBound && !selection.isEmpty ? position > start : position >= start
                if !removing, isAfter {
                    shift += 2
                } else if removing, position > start {
                    shift -= min(2, position - start)
                }
            }
            return position + shift
        }
        let newText = lines.joined(separator: "\n")
        let lower = map(selection.lowerBound, isLowerBound: true)
        let upper = max(lower, map(selection.upperBound))
        return Edit(text: newText, selection: lower..<min(upper, newText.count))
    }

    // MARK: Lists on Return

    /// What Return does in a bulleted line, given the text before and after a change: if the
    /// change inserted a single newline right after a bullet line, the new line becomes a
    /// bullet too; if the bullet line was empty, its bullet is removed and the list ends.
    ///
    /// - Returns: The corrected text and cursor offset, or `nil` when the change was anything
    ///   else.
    static func continueList(from old: String, to new: String) -> (text: String, cursor: Int)? {
        let oldCharacters = Array(old)
        let newCharacters = Array(new)
        guard newCharacters.count == oldCharacters.count + 1 else {
            return nil
        }
        // Where the one new character went.
        var position = 0
        while position < oldCharacters.count, oldCharacters[position] == newCharacters[position] {
            position += 1
        }
        guard newCharacters[position] == "\n",
            Array(newCharacters[(position + 1)...]) == Array(oldCharacters[position...])
        else {
            return nil
        }
        // The line the newline was typed in, up to the newline.
        let lineStart = (oldCharacters[..<position].lastIndex(of: "\n")).map { $0 + 1 } ?? 0
        let lineEnd = oldCharacters[position...].firstIndex(of: "\n") ?? oldCharacters.count
        let line = String(oldCharacters[lineStart..<lineEnd])
        guard let item = MarkdownBody.bulletItem(line) else {
            return nil
        }
        if item.allSatisfy(\.isWhitespace), position == lineEnd {
            // Return on an empty bullet: end the list, removing that bullet.
            var characters = oldCharacters
            characters.removeSubrange(lineStart..<lineEnd)
            return (String(characters), lineStart)
        }
        var characters = newCharacters
        characters.insert(contentsOf: "- ", at: position + 1)
        return (String(characters), position + 3)
    }

    // MARK: Links

    /// Replaces the selection with `[text](url)` and puts the cursor after it.
    static func insertLink(text: String, url: URL, in body: String, selection: Range<Int>) -> Edit {
        var characters = Array(body)
        let selection = clamped(selection, to: characters.count)
        let label = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let link = Array("[\(label.isEmpty ? url.absoluteString : label)](\(url.absoluteString))")
        characters.replaceSubrange(selection, with: link)
        let cursor = selection.lowerBound + link.count
        return Edit(text: String(characters), selection: cursor..<cursor)
    }

    private static func clamped(_ range: Range<Int>, to count: Int) -> Range<Int> {
        let lower = min(max(range.lowerBound, 0), count)
        let upper = min(max(range.upperBound, lower), count)
        return lower..<upper
    }
}
