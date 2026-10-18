import SwiftUI
import UIKit

/// Image data cropped to fill whatever frame it is given.
struct PhotoImage: View {
    let data: Data?
    var cornerRadius: CGFloat = 0

    var body: some View {
        Color.clear
            .overlay {
                if let data, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(.fill.tertiary)
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .accessibilityHidden(true)
    }
}

/// A photo's full image, decoded off the main actor at no more than `maxPixelSize`, with the
/// thumbnail shown until it is ready.
///
/// Use this wherever a photo is shown larger than its thumbnail. The bitmap is held only while
/// `isActive`, and the full image is picked up when it arrives after the record (external
/// storage syncs later than the thumbnail).
struct DownsampledPhotoImage: View {
    let photo: Photo
    let maxPixelSize: Int
    var contentMode = ContentMode.fill
    /// Whether to hold the decoded image. Pass `false` for pages that are out of view.
    var isActive = true

    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .overlay {
                if let image = image ?? thumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else {
                    Rectangle().fill(.fill.tertiary)
                }
            }
            .clipped()
            .loadsDownsampledImage(
                of: photo, maxPixelSize: maxPixelSize, isActive: isActive, into: $image)
    }

    private var thumbnail: UIImage? {
        photo.thumbnailData.flatMap(UIImage.init(data:))
    }
}

extension View {
    /// Decodes `photo`'s full image off the main actor at no more than `maxPixelSize` into
    /// `image` while `isActive`, and releases it otherwise. The full image is picked up when it
    /// arrives after the record (external storage syncs later than the thumbnail).
    func loadsDownsampledImage(
        of photo: Photo, maxPixelSize: Int, isActive: Bool, into image: Binding<UIImage?>
    ) -> some View {
        task(id: DownsampleLoadKey(isActive: isActive, hasImageData: photo.imageData != nil)) {
            guard isActive, let data = photo.imageData else {
                image.wrappedValue = nil
                return
            }
            let decoded = await ImageDownsampler.decode(data, maxPixelSize: maxPixelSize)
            if !Task.isCancelled, let decoded {
                image.wrappedValue = UIImage(cgImage: decoded)
            }
        }
    }
}

private struct DownsampleLoadKey: Equatable {
    let isActive: Bool
    let hasImageData: Bool
}
