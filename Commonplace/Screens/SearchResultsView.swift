import SwiftUI

/// A plain list of matching entries. Previewed only: I8 wires it to the search field.
struct SearchResultsView: View {
    let results: [Entry]

    @Environment(\.referenceDate) private var referenceDate

    var body: some View {
        List(results) { entry in
            NavigationLink(value: entry) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        TopicChip(topic: entry.topic)
                        Text("· \(EntryTimeline.shortDate(entry.date, now: referenceDate ?? .now))")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    Text(entry.body)
                        .font(.subheadline)
                        .lineLimit(2)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if results.isEmpty {
                ContentUnavailableView.search
            }
        }
    }
}

#Preview("Light") {
    SearchResultsPreview()
}

#Preview("Dark") {
    SearchResultsPreview()
        .preferredColorScheme(.dark)
}

/// Stands in for a search for "sunrise" across the seed.
private struct SearchResultsPreview: View {
    var body: some View {
        NavigationStack {
            SearchResultsView(results: results)
                .navigationTitle("Search")
        }
        .sampleData()
    }

    private var results: [Entry] {
        ["Sedona trip", "Stoic practice", "App ideas"]
            .flatMap { PreviewContainer.topic($0)?.liveEntries ?? [] }
            .filter { $0.body.localizedCaseInsensitiveContains("the") }
            .sorted { $0.date > $1.date }
    }
}
