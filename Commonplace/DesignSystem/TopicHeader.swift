import SwiftUI

/// The slim band at the top of a topic: description and entry count on a 14% topic tint.
///
/// The tint is drawn far above the band so it runs under the navigation bar and status bar,
/// and stops after the description.
struct TopicHeader: View {
    let topic: Topic

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !topic.summary.isEmpty {
                Text(topic.summary)
                    .font(.subheadline)
            }
            HStack(spacing: 6) {
                Circle()
                    .fill(topic.tint)
                    .frame(width: 8, height: 8)
                Text(EntryTimeline.entryCount(topic.liveEntries.count))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .bottom) {
            Rectangle()
                .fill(topic.tint.opacity(0.14))
                .frame(height: 1200)
        }
    }
}

#Preview("Light") {
    TopicHeaderPreview()
}

#Preview("Dark") {
    TopicHeaderPreview()
        .preferredColorScheme(.dark)
}

private struct TopicHeaderPreview: View {
    var body: some View {
        ScrollView {
            if let topic = PreviewContainer.topic("Sedona trip") {
                TopicHeader(topic: topic)
            }
        }
        .sampleData()
    }
}
