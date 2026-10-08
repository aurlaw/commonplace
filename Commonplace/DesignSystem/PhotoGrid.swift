import SwiftUI

/// An entry's photos: a hero tile with smaller tiles around it.
struct PhotoGrid: View {
    let photos: [Photo]
    var onSelect: (Int) -> Void = { _ in }

    var body: some View {
        PhotoGridLayout {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                Button {
                    onSelect(index)
                } label: {
                    tile(for: photo, at: index)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Photo \(index + 1) of \(photos.count)")
            }
        }
        .clipShape(.rect(cornerRadius: 14))
    }

    /// Small tiles show the stored thumbnail. Large tiles (the hero, or both tiles of a
    /// two-photo entry) show the full image downsampled, never the full-size bitmap.
    @ViewBuilder
    private func tile(for photo: Photo, at index: Int) -> some View {
        if index == 0 || photos.count <= 2 {
            DownsampledPhotoImage(photo: photo, maxPixelSize: Self.largeTilePixelSize)
                .accessibilityHidden(true)
        } else {
            PhotoImage(data: photo.thumbnailData)
        }
    }

    /// Enough for a full-width tile on a 3x screen.
    private static let largeTilePixelSize = 1200
}

/// Three columns. With three or more tiles the first is a 2×2 hero; one or two tiles share the
/// hero's height across the full width.
nonisolated struct PhotoGridLayout: Layout {
    var rowHeight: CGFloat = 118
    var spacing: CGFloat = 3

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let height = frames(count: subviews.count, width: width).map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        for (subview, frame) in zip(subviews, frames(count: subviews.count, width: bounds.width)) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    /// Tile frames in the layout's own coordinate space.
    func frames(count: Int, width: CGFloat) -> [CGRect] {
        let heroHeight = rowHeight * 2 + spacing
        switch count {
        case ...0:
            return []
        case 1:
            return [CGRect(x: 0, y: 0, width: width, height: heroHeight)]
        case 2:
            let half = (width - spacing) / 2
            return [
                CGRect(x: 0, y: 0, width: half, height: heroHeight),
                CGRect(x: half + spacing, y: 0, width: half, height: heroHeight),
            ]
        default:
            let cell = (width - spacing * 2) / 3
            let sideX = (cell + spacing) * 2
            var frames = [
                CGRect(x: 0, y: 0, width: cell * 2 + spacing, height: heroHeight),
                CGRect(x: sideX, y: 0, width: cell, height: rowHeight),
                CGRect(x: sideX, y: rowHeight + spacing, width: cell, height: rowHeight),
            ]
            for index in 0..<(count - 3) {
                frames.append(
                    CGRect(
                        x: CGFloat(index % 3) * (cell + spacing),
                        y: heroHeight + spacing + CGFloat(index / 3) * (rowHeight + spacing),
                        width: cell,
                        height: rowHeight
                    )
                )
            }
            return frames
        }
    }
}

#Preview("Light") {
    PhotoGridPreview()
}

#Preview("Dark") {
    PhotoGridPreview()
        .preferredColorScheme(.dark)
}

private struct PhotoGridPreview: View {
    var body: some View {
        ScrollView {
            if let entry = PreviewContainer.entry(in: "Sedona trip", at: 2) {
                PhotoGrid(photos: entry.sortedPhotos)
                    .padding(20)
            }
        }
        .sampleData()
    }
}
