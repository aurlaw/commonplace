import CoreGraphics

/// Zoom limits and geometry for the photo viewer's pages.
nonisolated enum PhotoZoom {
    /// Fit. Releasing a pinch below it springs back.
    static let minimumScale: CGFloat = 1
    /// Stored photos are at most 3000 px on the long edge, so detail runs out around here.
    static let maximumScale: CGFloat = 4
    /// Where a double-tap at fit zooms to, centered on the tapped point.
    static let doubleTapScale: CGFloat = 2.5

    /// Scales this close to fit count as fit, so float noise never suspends paging.
    private static let tolerance: CGFloat = 0.01

    static func isZoomed(_ scale: CGFloat) -> Bool {
        scale > minimumScale + tolerance
    }

    /// The size of an image of `imageSize` fitted inside `bounds`, keeping its aspect ratio.
    static func fittedSize(_ imageSize: CGSize, in bounds: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    /// The inset on each side that centers `content` in `bounds` along any axis where it is
    /// smaller; zero where it is larger.
    static func centeringInset(content: CGSize, in bounds: CGSize) -> CGSize {
        CGSize(
            width: max(0, (bounds.width - content.width) / 2),
            height: max(0, (bounds.height - content.height) / 2)
        )
    }

    /// The rect to zoom to for a double-tap at `point`, in the coordinates of the fitted content
    /// (`content` is its size at fit): `bounds` divided by `scale`, centered on the point and
    /// kept inside the content. Along an axis where the rect is larger than the content, it is
    /// centered on the content instead.
    static func doubleTapRect(
        at point: CGPoint, content: CGSize, bounds: CGSize, scale: CGFloat = doubleTapScale
    ) -> CGRect {
        let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
        func origin(_ center: CGFloat, length: CGFloat, content: CGFloat) -> CGFloat {
            guard length < content else { return (content - length) / 2 }
            return min(max(center - length / 2, 0), content - length)
        }
        return CGRect(
            x: origin(point.x, length: size.width, content: content.width),
            y: origin(point.y, length: size.height, content: content.height),
            width: size.width,
            height: size.height
        )
    }

    /// The next whole-number scale for a VoiceOver zoom action, within the limits.
    static func steppedScale(from scale: CGFloat, zoomingIn: Bool) -> CGFloat {
        let next =
            zoomingIn
            ? (scale + tolerance).rounded(.down) + 1
            : (scale - tolerance).rounded(.up) - 1
        return min(max(next, minimumScale), maximumScale)
    }
}

/// The viewer's selection, the selected page's zoom, and whether the chrome is hidden.
nonisolated struct PhotoViewerState: Equatable {
    /// Changing photos (a swipe or a filmstrip tap) resets the zoom and brings the chrome back.
    var selection: Int {
        didSet {
            guard selection != oldValue else { return }
            zoomScale = PhotoZoom.minimumScale
            isChromeHidden = false
        }
    }
    /// The selected page's zoom scale; other pages are always at fit.
    var zoomScale = PhotoZoom.minimumScale
    /// The toolbar, counter, caption, and filmstrip are hidden.
    var isChromeHidden = false

    init(selection: Int) {
        self.selection = selection
    }

    var isZoomed: Bool { PhotoZoom.isZoomed(zoomScale) }

    /// Swiping between photos works only at fit; zoomed, drags pan the photo.
    var isPagingEnabled: Bool { !isZoomed }

    mutating func toggleChrome() {
        isChromeHidden.toggle()
    }
}
