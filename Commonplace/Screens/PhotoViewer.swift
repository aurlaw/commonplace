import SwiftUI
import UIKit

/// Full-screen, swipeable photos with a counter, a caption, and a filmstrip. Always dark.
struct PhotoViewer: View {
    let photos: [Photo]
    let caption: String

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int

    init(photos: [Photo], startIndex: Int, caption: String) {
        self.photos = photos
        self.caption = caption
        _selection = State(initialValue: startIndex)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    PhotoPage(data: photo.imageData ?? photo.thumbnailData)
                        .tag(index)
                        .accessibilityLabel("Photo \(index + 1) of \(photos.count)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(.black)
            .safeAreaInset(edge: .bottom) {
                filmstrip
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("\(selection + 1) of \(photos.count)")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // Inert in the shell.
                    Button("Share", systemImage: "square.and.arrow.up") {}
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .environment(\.colorScheme, .dark)
    }

    private var filmstrip: some View {
        HStack(spacing: 3) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                Button {
                    withAnimation {
                        selection = index
                    }
                } label: {
                    PhotoImage(data: photo.thumbnailData, cornerRadius: 4)
                        .frame(width: index == selection ? 56 : 30, height: 42)
                        .opacity(index == selection ? 1 : 0.7)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show photo \(index + 1)")
            }
        }
        .animation(.default, value: selection)
        .padding(.bottom, 12)
    }
}

private struct PhotoPage: View {
    let data: Data?

    var body: some View {
        if let data, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Rectangle().fill(.fill.tertiary)
        }
    }
}

// The viewer is always dark, so one preview covers both modes.
#Preview("Viewer") {
    PhotoViewerPreview()
}

private struct PhotoViewerPreview: View {
    var body: some View {
        if let entry = PreviewContainer.entry(in: "Sedona trip", at: 2) {
            PhotoViewer(photos: entry.sortedPhotos, startIndex: 2, caption: "Oct 2 · 6:10 AM")
                .sampleData()
        }
    }
}
