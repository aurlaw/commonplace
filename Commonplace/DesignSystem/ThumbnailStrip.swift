import SwiftUI

/// A row of small square thumbnails, with a "+N" chip over the last one when there are more.
struct ThumbnailStrip: View {
    let photos: [Photo]
    var size: CGFloat = 46
    var maxVisible = 4

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(photos.prefix(maxVisible).enumerated()), id: \.element.id) {
                index, photo in
                PhotoImage(data: photo.thumbnailData, cornerRadius: 7)
                    .frame(width: size, height: size)
                    .overlay {
                        if index == maxVisible - 1, overflowCount > 0 {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(.black.opacity(0.45))
                            Text("+\(overflowCount)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(photos.count == 1 ? "1 photo" : "\(photos.count) photos")
    }

    /// Photos not shown as their own thumbnail; the last visible tile carries the chip.
    private var overflowCount: Int {
        photos.count > maxVisible ? photos.count - (maxVisible - 1) : 0
    }
}

#Preview("Light") {
    ThumbnailStripPreview()
}

#Preview("Dark") {
    ThumbnailStripPreview()
        .preferredColorScheme(.dark)
}

private struct ThumbnailStripPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach([3, 2, 5], id: \.self) { index in
                if let entry = PreviewContainer.entry(in: "Sedona trip", at: index) {
                    ThumbnailStrip(photos: entry.sortedPhotos)
                }
            }
        }
        .sampleData()
    }
}
