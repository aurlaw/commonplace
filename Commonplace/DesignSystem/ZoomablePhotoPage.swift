import SwiftUI
import UIKit

/// One page of the photo viewer: the photo's full image, zoomable with pinch and double-tap.
///
/// The image follows the `DownsampledPhotoImage` rules: decoded at up to
/// `PhotoLimits.imageMaxPixelSize` only while `isActive`, with the thumbnail shown until it is
/// ready. Zooming happens in a `UIScrollView`, which at fit doesn't take horizontal pans, so the
/// viewer's pager still swipes. `zoomScale` reports the scroll view's scale (when it crosses fit
/// and when a zoom ends) and zooms it when changed from outside; an inactive page resets to fit.
struct ZoomablePhotoPage: View {
    let photo: Photo
    let isActive: Bool
    @Binding var zoomScale: CGFloat
    /// A single tap, recognized once a double-tap has failed.
    let onSingleTap: () -> Void

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image = image ?? thumbnail {
                ZoomingImageView(
                    image: image,
                    isActive: isActive,
                    zoomScale: $zoomScale,
                    onSingleTap: onSingleTap
                )
            } else {
                Rectangle()
                    .fill(.fill.tertiary)
                    .onTapGesture(perform: onSingleTap)
            }
        }
        .loadsDownsampledImage(
            of: photo, maxPixelSize: PhotoLimits.imageMaxPixelSize, isActive: isActive,
            into: $image)
    }

    private var thumbnail: UIImage? {
        photo.thumbnailData.flatMap(UIImage.init(data:))
    }
}

private struct ZoomingImageView: UIViewRepresentable {
    let image: UIImage
    let isActive: Bool
    @Binding var zoomScale: CGFloat
    let onSingleTap: () -> Void

    func makeUIView(context: Context) -> ZoomingScrollView {
        ZoomingScrollView()
    }

    func updateUIView(_ view: ZoomingScrollView, context: Context) {
        view.animatesZoom = !context.environment.accessibilityReduceMotion
        view.onSingleTap = onSingleTap
        view.onZoomChange = { zoomScale = $0 }
        view.setImage(image)
        if isActive {
            view.apply(requestedScale: zoomScale)
        } else {
            view.resetZoom()
        }
    }
}

/// A scroll view zooming one image view, which is sized to fit the bounds at scale 1 and kept
/// centered while it is smaller than them.
private final class ZoomingScrollView: UIScrollView, UIScrollViewDelegate {
    var animatesZoom = true
    var onSingleTap: (() -> Void)?
    var onZoomChange: ((CGFloat) -> Void)?

    private let imageView = UIImageView()
    /// The bounds size the image view was last fitted to.
    private var fittedBounds = CGSize.zero
    /// The last scale reported through `onZoomChange` (or requested from outside), so a
    /// requested scale can be told apart from one this view reported.
    private var reportedScale = PhotoZoom.minimumScale
    /// Set while this view changes its own zoom, so that change isn't reported.
    private var isApplying = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = PhotoZoom.minimumScale
        maximumZoomScale = PhotoZoom.maximumScale
        bouncesZoom = true
        alwaysBounceHorizontal = false
        alwaysBounceVertical = false
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        decelerationRate = .fast
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear

        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(singleTapped))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Shows `image`. The thumbnail and the full image share an aspect ratio, so swapping one
    /// for the other keeps the zoom; a different shape refits at scale 1.
    func setImage(_ image: UIImage) {
        guard imageView.image !== image else { return }
        let previous = imageView.image?.size
        imageView.image = image
        if let previous, Self.sameAspect(previous, image.size) { return }
        resetZoom()
        fittedBounds = .zero
        setNeedsLayout()
    }

    /// Zooms to a scale set from outside (a VoiceOver zoom action); ignores the scale this view
    /// reported itself.
    func apply(requestedScale scale: CGFloat) {
        guard abs(scale - reportedScale) > 0.001 else { return }
        reportedScale = scale
        let clamped = min(max(scale, minimumZoomScale), maximumZoomScale)
        performZoom(reports: false) { $0.setZoomScale(clamped, animated: false) }
    }

    /// Returns to fit without animating, as an out-of-view page does.
    func resetZoom() {
        reportedScale = PhotoZoom.minimumScale
        guard zoomScale != minimumZoomScale else { return }
        isApplying = true
        setZoomScale(minimumZoomScale, animated: false)
        centerContent()
        isApplying = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != fittedBounds {
            refit()
        }
    }

    /// Fits the image view to new bounds (first layout, rotation, chrome hiding), keeping a
    /// zoomed photo at its scale around the same point.
    private func refit() {
        guard bounds.width > 0, bounds.height > 0, let image = imageView.image else { return }
        fittedBounds = bounds.size
        let scale = zoomScale
        let center = normalizedVisibleCenter()

        isApplying = true
        setZoomScale(minimumZoomScale, animated: false)
        let fitted = PhotoZoom.fittedSize(image.size, in: bounds.size)
        imageView.frame = CGRect(origin: .zero, size: fitted)
        contentSize = fitted
        if PhotoZoom.isZoomed(scale) {
            setZoomScale(scale, animated: false)
            centerContent()
            restoreVisibleCenter(center)
        } else {
            centerContent()
            contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
        }
        isApplying = false
    }

    private func centerContent() {
        let inset = PhotoZoom.centeringInset(content: contentSize, in: bounds.size)
        contentInset = UIEdgeInsets(
            top: inset.height, left: inset.width, bottom: inset.height, right: inset.width)
    }

    /// The point of the content at the middle of the screen, as a fraction of the content size.
    private func normalizedVisibleCenter() -> CGPoint {
        guard contentSize.width > 0, contentSize.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(
            x: (contentOffset.x + bounds.width / 2) / contentSize.width,
            y: (contentOffset.y + bounds.height / 2) / contentSize.height
        )
    }

    private func restoreVisibleCenter(_ center: CGPoint) {
        let x = center.x * contentSize.width - bounds.width / 2
        let y = center.y * contentSize.height - bounds.height / 2
        let maxX = contentSize.width - bounds.width + contentInset.right
        let maxY = contentSize.height - bounds.height + contentInset.bottom
        contentOffset = CGPoint(
            x: min(max(x, -contentInset.left), maxX),
            y: min(max(y, -contentInset.top), maxY)
        )
    }

    /// Runs a zoom change, animated unless Reduce Motion is on. The change is applied
    /// synchronously (the animation only presents it), so the final scale is known right after.
    private func performZoom(reports: Bool, _ change: @escaping (ZoomingScrollView) -> Void) {
        isApplying = true
        if animatesZoom {
            UIView.animate(
                withDuration: 0.3, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]
            ) {
                change(self)
            }
        } else {
            change(self)
        }
        isApplying = false
        if reports {
            report(zoomScale)
        }
    }

    private func report(_ scale: CGFloat) {
        reportedScale = scale
        onZoomChange?(scale)
    }

    private static func sameAspect(_ a: CGSize, _ b: CGSize) -> Bool {
        guard a.height > 0, b.height > 0 else { return false }
        let ratio = (a.width / a.height) / (b.width / b.height)
        return abs(ratio - 1) < 0.02
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        if PhotoZoom.isZoomed(zoomScale) {
            performZoom(reports: true) { $0.setZoomScale($0.minimumZoomScale, animated: false) }
        } else {
            let rect = PhotoZoom.doubleTapRect(
                at: gesture.location(in: imageView), content: imageView.bounds.size,
                bounds: bounds.size)
            performZoom(reports: true) { $0.zoom(to: rect, animated: false) }
        }
    }

    @objc private func singleTapped() {
        onSingleTap?()
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
        // Report while pinching only when the scale crosses fit, which is what suspends
        // paging; the final scale is reported when the zoom ends.
        if !isApplying, PhotoZoom.isZoomed(zoomScale) != PhotoZoom.isZoomed(reportedScale) {
            report(zoomScale)
        }
    }

    func scrollViewDidEndZooming(
        _ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat
    ) {
        if !isApplying {
            report(scale)
        }
    }
}
