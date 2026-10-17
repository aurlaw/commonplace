import SwiftData
import SwiftUI

/// Matching topics and entries for a search on the topics list. Opening an entry pushes its
/// topic and then the entry, so the topic chip and Back lead to the topic, and Back again to
/// these results.
struct SearchResultsView: View {
    let results: SearchResults
    let query: SearchQuery
    /// As typed, for the empty state.
    let searchText: String
    let open: (SearchResultsView.Destination) -> Void

    enum Destination {
        case topic(Topic)
        case entry(Entry)
    }

    var body: some View {
        List {
            if !results.topics.isEmpty {
                Section(results.topics.count == 1 ? "1 Topic" : "\(results.topics.count) Topics") {
                    ForEach(results.topics) { topic in
                        if topic.isAvailable {
                            Button {
                                open(.topic(topic))
                            } label: {
                                TopicRow(topic: topic, marksArchived: true)
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            if !results.entries.isEmpty {
                Section {
                    ForEach(results.entries) { entry in
                        if entry.isAvailable {
                            Button {
                                open(.entry(entry))
                            } label: {
                                SearchResultRow(entry: entry, query: query)
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                } header: {
                    Text(EntryTimeline.entryCount(results.entries.count).capitalized)
                } footer: {
                    if results.isCapped {
                        Text("Showing the \(SearchResults.entryLimit) most recent matches")
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if results.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }
}

/// An entry in search results: topic, date, and the matched words in context.
private struct SearchResultRow: View {
    let entry: Entry
    let query: SearchQuery

    @Environment(\.referenceDate) private var referenceDate

    var body: some View {
        let snippet = SearchSnippet(body: entry.body, placeName: entry.placeName, query: query)
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    TopicChip(topic: entry.topic)
                    Text("· \(date)")
                    if entry.topic?.isArchived == true {
                        Text("· Archived")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                Text(Self.highlighted(snippet.text, snippet.highlights))
                    .font(.subheadline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let placeName = snippet.placeName {
                    Label {
                        Text(Self.highlighted(placeName, snippet.placeNameHighlights))
                    } icon: {
                        Image(systemName: "location.fill")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let thumbnail = entry.sortedPhotos.first?.thumbnailData {
                PhotoImage(data: thumbnail, cornerRadius: 8)
                    .frame(width: 48, height: 48)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(snippet))
    }

    private var date: String {
        EntryTimeline.shortDate(entry.date, now: referenceDate ?? .now)
    }

    private func accessibilityText(_ snippet: SearchSnippet) -> String {
        var parts = [entry.topic?.title ?? "No topic", date]
        if entry.topic?.isArchived == true {
            parts.append("Archived")
        }
        parts.append(snippet.text)
        if let placeName = snippet.placeName {
            parts.append(placeName)
        }
        return parts.joined(separator: ", ")
    }

    /// The matched words in bold, in the primary color.
    private static func highlighted(
        _ text: String, _ ranges: [Range<String.Index>]
    ) -> AttributedString {
        var attributed = AttributedString()
        var cursor = text.startIndex
        for range in ranges {
            attributed += AttributedString(text[cursor..<range.lowerBound])
            var match = AttributedString(text[range])
            match.inlinePresentationIntent = .stronglyEmphasized
            match.foregroundColor = .primary
            attributed += match
            cursor = range.upperBound
        }
        attributed += AttributedString(text[cursor...])
        return attributed
    }
}

#Preview("Light") {
    SearchResultsPreview(text: "sunrise")
}

#Preview("Dark") {
    SearchResultsPreview(text: "sunrise")
        .preferredColorScheme(.dark)
}

#Preview("Place name") {
    SearchResultsPreview(text: "trailhead")
}

#Preview("No results") {
    SearchResultsPreview(text: "zebra")
}

/// A search across the seed.
private struct SearchResultsPreview: View {
    let text: String

    var body: some View {
        NavigationStack {
            let query = SearchQuery(text)
            let results =
                (try? EntrySearch(context: PreviewContainer.shared.mainContext).results(for: query))
                ?? SearchResults(query: query, topics: [], entries: [])
            SearchResultsView(results: results, query: query, searchText: text) { _ in }
                .navigationTitle("Search")
        }
        .sampleData()
    }
}
