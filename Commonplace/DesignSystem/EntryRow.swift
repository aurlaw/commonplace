import SwiftUI

/// An entry in a topic timeline. Leads with the day so month groups scan like a calendar.
struct EntryRow: View {
    let entry: Entry

    var body: some View {
        // A row can outlive its entry for a moment after a permanent delete.
        if entry.isAvailable {
            content
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Text(EntryTimeline.dayNumber(entry.date))
                    .font(.title2.weight(.semibold))
                Text(EntryTimeline.weekday(entry.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(EntryTimeline.time(entry.date))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(entry.body)
                    .font(.subheadline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !entry.sortedPhotos.isEmpty {
                    ThumbnailStrip(photos: entry.sortedPhotos)
                        .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(.rect)
    }
}

#Preview("Light") {
    EntryRowPreview()
}

#Preview("Dark") {
    EntryRowPreview()
        .preferredColorScheme(.dark)
}

private struct EntryRowPreview: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach([5, 4, 3], id: \.self) { index in
                if let entry = PreviewContainer.entry(in: "Sedona trip", at: index) {
                    EntryRow(entry: entry)
                    Divider().padding(.leading, 64)
                }
            }
        }
        .sampleData()
    }
}
