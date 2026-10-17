import Foundation
import LinkPresentation
import Testing

@testable import Commonplace

// MARK: Blocks

struct MarkdownBlockTests {
    @Test func plainTextIsOneParagraphWithItsBlankLinesKept() {
        let body = "First paragraph.\n\nSecond paragraph.\nSame paragraph."
        #expect(MarkdownBody.blocks(body) == [.paragraph(body)])
    }

    @Test func consecutiveBulletLinesFormOneList() {
        let body = "- one\n* two\n- three"
        #expect(MarkdownBody.blocks(body) == [.bulletList(["one", "two", "three"])])
    }

    @Test func mixedContentSplitsIntoBlocksInOrder() {
        let body = "Packing:\n- hat\n- gloves\n\nThen the trail.\n\n- water"
        #expect(
            MarkdownBody.blocks(body) == [
                .paragraph("Packing:"),
                .bulletList(["hat", "gloves"]),
                .paragraph("Then the trail."),
                .bulletList(["water"]),
            ])
    }

    @Test func blankLinesAroundBlocksAreDropped() {
        #expect(MarkdownBody.blocks("\n\nHello\n\n") == [.paragraph("Hello")])
        #expect(MarkdownBody.blocks("") == [])
        #expect(MarkdownBody.blocks("\n \n") == [])
    }

    @Test func aDashMidSentenceIsNotABullet() {
        let body = "Up at 5 - down by 9.\n-not a bullet\n -nor this"
        #expect(MarkdownBody.blocks(body) == [.paragraph(body)])
    }
}

// MARK: Inline

struct MarkdownInlineTests {
    private func runs(_ text: String) -> [(String, InlinePresentationIntent?, URL?)] {
        let attributed = MarkdownBody.inline(text)
        return attributed.runs.map {
            (String(attributed[$0.range].characters), $0.inlinePresentationIntent, $0.link)
        }
    }

    private func text(_ markdown: String) -> String {
        String(MarkdownBody.inline(markdown).characters)
    }

    @Test func boldAndItalic() {
        let result = runs("a **bold** and *italic* word")
        #expect(text("a **bold** and *italic* word") == "a bold and italic word")
        #expect(result.contains { $0.0 == "bold" && $0.1 == .stronglyEmphasized })
        #expect(result.contains { $0.0 == "italic" && $0.1 == .emphasized })
    }

    @Test func nestedBoldAndItalic() {
        let result = runs("***both***")
        #expect(text("***both***") == "both")
        #expect(result.first?.1 == [.emphasized, .stronglyEmphasized])
    }

    @Test func markdownLink() {
        let result = runs("See [Elote](https://elotecafe.com).")
        #expect(text("See [Elote](https://elotecafe.com).") == "See Elote.")
        #expect(result.contains { $0.0 == "Elote" && $0.2 == URL(string: "https://elotecafe.com") })
    }

    @Test func bareURLIsLinked() {
        let markdown = "Trail info: https://example.com/trail?id=1 today"
        let link = runs(markdown).first { $0.2 != nil }
        #expect(link?.0 == "https://example.com/trail?id=1")
        #expect(link?.2 == URL(string: "https://example.com/trail?id=1"))
    }

    @Test func aURLInsideAMarkdownLinkIsNotLinkedTwice() {
        let result = runs("[https://a.example.com](https://b.example.com)")
        let links = result.compactMap(\.2)
        #expect(links == [URL(string: "https://b.example.com")])
    }

    @Test func disallowedSchemesAreNotLinks() {
        let result = runs("[run](javascript:alert(1)) and [mail](mailto:me@example.com)")
        #expect(!result.contains { $0.2?.scheme == "javascript" })
        #expect(result.first?.0.hasPrefix("run") == true)
        #expect(result.contains { $0.0 == "mail" && $0.2 == URL(string: "mailto:me@example.com") })
    }

    @Test func barePlainHostsAndEmailsAreNotLinked() {
        #expect(runs("example.com or me@example.com").allSatisfy { $0.2 == nil })
    }

    @Test func unsupportedSyntaxShowsLiterally() {
        #expect(
            text("`code` ~strike~ snake_case_word <b>x</b> &amp;")
                == "`code` ~strike~ snake_case_word <b>x</b> &amp;")
        #expect(runs("`code`").allSatisfy { $0.1 == nil })
        #expect(text("# Not a heading") == "# Not a heading")
        #expect(text("1. Not a list") == "1. Not a list")
        #expect(text("> Not a quote") == "> Not a quote")
    }

    @Test func malformedMarkdownKeepsEveryCharacter() {
        #expect(text("**unclosed bold") == "**unclosed bold")
        #expect(text("[no link](") == "[no link](")
        #expect(text("a * b * c") == "a * b * c")
    }

    @Test func lineBreaksArePreserved() {
        #expect(text("one\ntwo\n\nthree") == "one\ntwo\n\nthree")
    }
}

// MARK: Plain projection and links

struct MarkdownPlainTextTests {
    @Test func syntaxIsRemovedAndLinkTextKept() {
        let body = "**Dinner** at [Elote](https://elotecafe.com), *worth it*."
        #expect(SearchableText.plain(body) == "Dinner at Elote, worth it.")
    }

    @Test func bulletsFlattenToLines() {
        let body = "Packing:\n- **hat**\n- gloves"
        #expect(SearchableText.plain(body) == "Packing:\nhat\ngloves")
    }

    @Test func plainEntriesAreUnchanged() {
        let body = "Cathedral Rock at first light.\n\nNext time: a weekday — 6:15, 91°."
        #expect(SearchableText.plain(body) == body)
    }

    @Test func searchIgnoresFormatting() {
        let query = SearchQuery("fire-roasted corn")
        #expect(query.matches(SearchableText.plain("Get the **fire-roasted corn**.")))
        let snippet = SearchSnippet(
            body: "Get the **fire-roasted corn**.", placeName: nil, query: SearchQuery("corn"))
        #expect(snippet.text == "Get the fire-roasted corn.")
    }

    @Test func linksAreUniqueHTTPInReadingOrder() {
        let body = """
            [B](https://b.example.com) then https://a.example.com
            - again https://b.example.com
            - [mail](mailto:me@example.com) and [ftp](ftp://c.example.com)
            """
        #expect(
            MarkdownBody.links(in: body) == [
                URL(string: "https://b.example.com")!, URL(string: "https://a.example.com")!,
            ])
    }
}

// MARK: Editing

struct MarkdownEditingTests {
    private func edit(
        _ style: MarkdownEditing.Style, _ text: String, _ selection: Range<Int>
    ) -> MarkdownEditing.Edit {
        MarkdownEditing.toggle(style, in: text, selection: selection)
    }

    @Test func boldWrapsTheSelection() {
        let result = edit(.bold, "a word here", 2..<6)
        #expect(result.text == "a **word** here")
        #expect(result.selection == 4..<8)
    }

    @Test func boldUnwrapsWhenTheMarkersAreOutsideOrSelected() {
        #expect(
            edit(.bold, "a **word** here", 4..<8) == .init(text: "a word here", selection: 2..<6))
        #expect(
            edit(.bold, "a **word** here", 2..<10) == .init(text: "a word here", selection: 2..<6))
    }

    @Test func emptySelectionInsertsThePairWithTheCursorBetween() {
        #expect(edit(.bold, "ab", 1..<1) == .init(text: "a****b", selection: 3..<3))
        #expect(edit(.italic, "", 0..<0) == .init(text: "**", selection: 1..<1))
    }

    @Test func italicWrapsAndUnwraps() {
        #expect(edit(.italic, "a word", 2..<6) == .init(text: "a *word*", selection: 3..<7))
        #expect(edit(.italic, "a *word*", 3..<7) == .init(text: "a word", selection: 2..<6))
    }

    @Test func italicInsideBoldWrapsRatherThanUnwrapping() {
        // The asterisks either side are bold's, not italic's.
        #expect(edit(.italic, "**word**", 2..<6) == .init(text: "***word***", selection: 3..<7))
        #expect(edit(.italic, "***word***", 3..<7) == .init(text: "**word**", selection: 2..<6))
        #expect(edit(.bold, "***word***", 3..<7) == .init(text: "*word*", selection: 1..<5))
    }

    @Test func edgeWhitespaceStaysOutsideTheMarkers() {
        #expect(edit(.bold, "a word here", 1..<7).text == "a **word** here")
    }

    @Test func bulletToggleOnOneLine() {
        let on = MarkdownEditing.toggleBullets(in: "one\ntwo", selection: 5..<5)
        #expect(on == .init(text: "one\n- two", selection: 7..<7))

        let off = MarkdownEditing.toggleBullets(in: on.text, selection: on.selection)
        #expect(off == .init(text: "one\ntwo", selection: 5..<5))
    }

    @Test func bulletToggleOnAnEmptyLineStartsAList() {
        #expect(
            MarkdownEditing.toggleBullets(in: "", selection: 0..<0)
                == .init(text: "- ", selection: 2..<2))
    }

    @Test func bulletToggleOnManyLinesSkipsBlankOnes() {
        let text = "one\n\ntwo\nthree"
        let on = MarkdownEditing.toggleBullets(in: text, selection: 0..<text.count)
        #expect(on.text == "- one\n\n- two\n- three")
        #expect(on.selection == 0..<on.text.count)

        let off = MarkdownEditing.toggleBullets(in: on.text, selection: on.selection)
        #expect(off.text == text)
    }

    @Test func bulletToggleAddsToTheLinesMissingOne() {
        let result = MarkdownEditing.toggleBullets(in: "- one\ntwo", selection: 0..<9)
        #expect(result.text == "- one\n- two")
    }

    @Test func aSelectionEndingAtALineStartDoesNotTouchThatLine() {
        let result = MarkdownEditing.toggleBullets(in: "one\ntwo", selection: 0..<4)
        #expect(result.text == "- one\ntwo")
    }

    @Test func returnInABulletContinuesTheList() {
        let old = "- hat"
        let new = "- hat\n"
        let result = MarkdownEditing.continueList(from: old, to: new)
        #expect(result?.text == "- hat\n- ")
        #expect(result?.cursor == 8)
    }

    @Test func returnMidBulletSplitsIntoTwoBullets() {
        let result = MarkdownEditing.continueList(from: "- hatgloves", to: "- hat\ngloves")
        #expect(result?.text == "- hat\n- gloves")
        #expect(result?.cursor == 8)
    }

    @Test func returnOnAnEmptyBulletEndsTheList() {
        let result = MarkdownEditing.continueList(from: "- hat\n- ", to: "- hat\n- \n")
        #expect(result?.text == "- hat\n")
        #expect(result?.cursor == 6)
    }

    @Test func otherChangesAreLeftAlone() {
        #expect(MarkdownEditing.continueList(from: "hat", to: "hat\n") == nil)
        #expect(MarkdownEditing.continueList(from: "- hat", to: "- hats") == nil)
        #expect(MarkdownEditing.continueList(from: "- hat", to: "- hat\n\n") == nil)
        #expect(MarkdownEditing.continueList(from: "- hat\n- ", to: "- hat\n") == nil)
    }

    @Test func insertLinkReplacesTheSelection() {
        let url = URL(string: "https://elotecafe.com")!
        let result = MarkdownEditing.insertLink(
            text: "Elote", url: url, in: "Dinner at Elote.", selection: 10..<15)
        #expect(result.text == "Dinner at [Elote](https://elotecafe.com).")
        #expect(result.selection == 40..<40)

        let noText = MarkdownEditing.insertLink(text: " ", url: url, in: "", selection: 0..<0)
        #expect(noText.text == "[https://elotecafe.com](https://elotecafe.com)")
    }

    @Test func linkInputAcceptsWebAndMailURLs() {
        #expect(
            LinkInput.url(from: " https://example.com/a ") == URL(string: "https://example.com/a"))
        #expect(LinkInput.url(from: "example.com") == URL(string: "https://example.com"))
        #expect(
            LinkInput.url(from: "mailto:me@example.com") == URL(string: "mailto:me@example.com"))
        #expect(LinkInput.url(from: "javascript:alert(1)") == nil)
        #expect(LinkInput.url(from: "not a url") == nil)
        #expect(LinkInput.url(from: "localhost") == nil)
    }
}

// MARK: Metadata cache

@MainActor
final class LinkMetadataCacheTests {
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "LinkMetadataCacheTests-\(UUID().uuidString)")
    private let url = URL(string: "https://elotecafe.com")!
    private var fetches = 0
    private var isOnline = true

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeService() -> CachedLinkMetadataService {
        CachedLinkMetadataService(directory: directory) { [unowned self] url in
            fetches += 1
            guard isOnline else {
                return nil
            }
            let metadata = LPLinkMetadata()
            metadata.url = url
            metadata.title = "Elote Cafe"
            return try? NSKeyedArchiver.archivedData(
                withRootObject: metadata, requiringSecureCoding: true)
        }
    }

    @Test func aMissFetchesAndCaches() async {
        let service = makeService()

        let metadata = await service.metadata(for: url)

        #expect(metadata?.title == "Elote Cafe")
        #expect(fetches == 1)
        #expect(FileManager.default.fileExists(atPath: service.cacheFile(for: url).path()))
    }

    @Test func aHitIsServedWithoutFetchingEvenOffline() async {
        _ = await makeService().metadata(for: url)
        isOnline = false

        // A new session reads the archive.
        let metadata = await makeService().metadata(for: url)

        #expect(metadata?.title == "Elote Cafe")
        #expect(fetches == 1)
        #expect(await makeService().title(for: url) == "Elote Cafe")
    }

    @Test func anEvictedEntryIsFetchedAgain() async throws {
        let service = makeService()
        _ = await service.metadata(for: url)
        try FileManager.default.removeItem(at: service.cacheFile(for: url))

        let metadata = await makeService().metadata(for: url)

        #expect(metadata?.title == "Elote Cafe")
        #expect(fetches == 2)
    }

    @Test func aFailureIsNotRetriedInTheSameSession() async {
        isOnline = false
        let service = makeService()

        #expect(await service.metadata(for: url) == nil)
        isOnline = true
        #expect(await service.metadata(for: url) == nil)
        #expect(fetches == 1)

        // The next session tries again.
        #expect(await makeService().metadata(for: url)?.title == "Elote Cafe")
        #expect(fetches == 2)
    }

    @Test func cacheKeysAreStableAndDistinct() {
        let a = CachedLinkMetadataService.key(for: URL(string: "https://a.example.com")!)
        #expect(a == CachedLinkMetadataService.key(for: URL(string: "https://a.example.com")!))
        #expect(a != CachedLinkMetadataService.key(for: URL(string: "https://b.example.com")!))
    }
}
