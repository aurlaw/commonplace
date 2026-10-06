import SwiftUI

/// Color dot + topic name.
struct TopicChip: View {
    let topic: Topic?
    var dotSize: CGFloat = 8

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(topic?.tint ?? .secondary)
                .frame(width: dotSize, height: dotSize)
            Text(topic?.title ?? "No topic")
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Light") {
    TopicChip(topic: PreviewContainer.topic("Sedona trip"))
        .sampleData()
}

#Preview("Dark") {
    TopicChip(topic: PreviewContainer.topic("Sedona trip"))
        .sampleData()
        .preferredColorScheme(.dark)
}
