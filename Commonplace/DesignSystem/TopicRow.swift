import SwiftUI

/// A topic in the topics list: color bar, title, last-entry label, and entry count.
struct TopicRow: View {
    let topic: Topic

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
        guard let date = topic.lastEntryDate else {
            return "No entries"
        }
        return EntryTimeline.lastEntryLabel(for: date, now: referenceDate ?? .now)
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
