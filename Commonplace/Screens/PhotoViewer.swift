import SwiftUI
import UIKit

/// Full-screen, swipeable photos with a counter, a caption, and a filmstrip. Always dark.
///
/// Photos zoom with pinch and double-tap (`ZoomablePhotoPage`); swiping pages only at fit, and
/// changing photos resets the zoom. A single tap hides or shows the chrome.
struct PhotoViewer: View {
    let photos: [Photo]
    let caption: String

    @Environment(\.dismiss) private var dismiss
    @State private var state: PhotoViewerState

    init(photos: [Photo], startIndex: Int, caption: String) {
        self.photos = photos
        self.caption = caption
        _state = State(initialValue: PhotoViewerState(selection: startIndex))
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $state.selection) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    // Only the visible page holds a full-size bitmap, and only it can be zoomed.
                    let isActive = index == state.selection
                    ZoomablePhotoPage(
                        photo: photo,
                        isActive: isActive,
                        zoomScale: isActive ? $state.zoomScale : .constant(PhotoZoom.minimumScale),
                        onSingleTap: toggleChrome
                    )
                    .tag(index)
                    .accessibilityElement()
                    .accessibilityAddTraits(.isImage)
                    .accessibilityLabel("Photo \(index + 1) of \(photos.count)")
                    .accessibilityZoomAction(zoom)
                    .accessibilityAction(
                        named: state.isChromeHidden ? "Show controls" : "Hide controls",
                        toggleChrome)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // Zoomed, drags pan the photo; zoom out to move on.
            .scrollDisabled(!state.isPagingEnabled)
            .background(.black)
            .safeAreaInset(edge: .bottom) {
                filmstrip
                    .opacity(state.isChromeHidden ? 0 : 1)
                    .allowsHitTesting(!state.isChromeHidden)
                    .accessibilityHidden(state.isChromeHidden)
                    .animation(.easeInOut(duration: 0.2), value: state.isChromeHidden)
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
                        Text("\(state.selection + 1) of \(photos.count)")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // Inert: sharing isn't planned yet.
                    Button("Share", systemImage: "square.and.arrow.up") {}
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarVisibility(state.isChromeHidden ? .hidden : .visible, for: .navigationBar)
        }
        .statusBarHidden(state.isChromeHidden)
        .environment(\.colorScheme, .dark)
    }

    private func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.2)) {
            state.toggleChrome()
        }
    }

    /// VoiceOver zoom: one whole step in or out, applied to the page by `ZoomablePhotoPage`.
    private func zoom(_ action: AccessibilityZoomGestureAction) {
        let zoomingIn = action.direction == .zoomIn
        let scale = PhotoZoom.steppedScale(from: state.zoomScale, zoomingIn: zoomingIn)
        guard scale != state.zoomScale else { return }
        state.zoomScale = scale
        AccessibilityNotification.Announcement(zoomingIn ? "Zoomed in" : "Zoomed out").post()
    }

    private var filmstrip: some View {
        HStack(spacing: 3) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                Button {
                    withAnimation {
                        state.selection = index
                    }
                } label: {
                    PhotoImage(data: photo.thumbnailData, cornerRadius: 4)
                        .frame(width: index == state.selection ? 56 : 30, height: 42)
                        .opacity(index == state.selection ? 1 : 0.7)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show photo \(index + 1)")
            }
        }
        .animation(.default, value: state.selection)
        .padding(.bottom, 12)
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
