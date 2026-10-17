import SwiftUI

/// A topic in the topics list: color bar, title, last-entry label, and entry count.
struct TopicRow: View {
    let topic: Topic
    /// Says "Archived" before the last-entry label, for lists that mix archived and live
    /// topics (search results).
    var marksArchived = false

    @Environment(\.referenceDate) private var referenceDate

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(topic.tint)
                .frame(width: 4, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(topic.title)
                Text(lastEntryLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(topic.liveEntries.count, format: .number)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(topic.title), \(EntryTimeline.entryCount(topic.liveEntries.count)), \(lastEntryLabel)"
        )
    }

    private var lastEntryLabel: String {
        let label =
            topic.lastEntryDate.map {
                EntryTimeline.lastEntryLabel(for: $0, now: referenceDate ?? .now)
            } ?? "No entries"
        return marksArchived && topic.isArchived ? "Archived · \(label)" : label
    }
}

#Preview("Light") {
    TopicRowPreview()
}

#Preview("Dark") {
    TopicRowPreview()
        .preferredColorScheme(.dark)
}

private struct TopicRowPreview: View {
    var body: some View {
        List {
            ForEach(["Stoic practice", "Sedona trip", "Cigars"], id: \.self) { title in
                if let topic = PreviewContainer.topic(title) {
                    TopicRow(topic: topic)
                }
            }
        }
        .sampleData()
    }
}
