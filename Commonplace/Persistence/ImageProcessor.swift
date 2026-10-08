import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Sizes and limits for stored photos, in one place.
nonisolated enum PhotoLimits {
    static let maxPhotosPerEntry = 20
    /// Long edge of a stored image, in pixels. Originals are downscaled to this.
    static let imageMaxPixelSize = 3000
    static let imageQuality = 0.8
    /// Long edge of a stored thumbnail, in pixels.
    static let thumbnailMaxPixelSize = 400
    static let thumbnailQuality = 0.7
}

/// A picked photo, ready to store: both are JPEG data with orientation baked in and no
/// metadata.
nonisolated struct ProcessedImage: Sendable, Equatable {
    let image: Data
    let thumbnail: Data
}

nonisolated enum ImageProcessingError: Error {
    /// The data isn't an image ImageIO can read.
    case undecodable
    case encodingFailed
}

/// Turns picked image data into what an entry stores. Injected so tests can use a fake.
nonisolated protocol ImageProcessor: Sendable {
    func process(_ data: Data) async throws -> ProcessedImage
}

/// Downscales with ImageIO, which downsamples without decoding the full image into memory.
nonisolated struct ImageIOProcessor: ImageProcessor {
    @concurrent
    func process(_ data: Data) async throws -> ProcessedImage {
        let image = try Self.jpegData(
            from: data,
            maxPixelSize: PhotoLimits.imageMaxPixelSize,
            quality: PhotoLimits.imageQuality
        )
        // The thumbnail is made from the downscaled image, which is cheaper than the original.
        let thumbnail = try Self.jpegData(
            from: image,
            maxPixelSize: PhotoLimits.thumbnailMaxPixelSize,
            quality: PhotoLimits.thumbnailQuality
        )
        return ProcessedImage(image: image, thumbnail: thumbnail)
    }

    /// JPEG data no larger than `maxPixelSize` on its long edge. Smaller images are re-encoded
    /// at their own size, not upscaled.
    static func jpegData(from data: Data, maxPixelSize: Int, quality: Double) throws -> Data {
        guard let image = ImageDownsampler.cgImage(from: data, maxPixelSize: maxPixelSize) else {
            throw ImageProcessingError.undecodable
        }
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, UTType.jpeg.identifier as CFString, 1, nil
            )
        else {
            throw ImageProcessingError.encodingFailed
        }
        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageProcessingError.encodingFailed
        }
        return output as Data
    }
}

/// Decodes image data at a reduced size, so a screen never holds a bitmap larger than it shows.
nonisolated enum ImageDownsampler {
    /// The image no larger than `maxPixelSize` on its long edge, upright (EXIF orientation
    /// applied), or `nil` if the data isn't a readable image.
    static func cgImage(from data: Data, maxPixelSize: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let options =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ] as CFDictionary
        if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) {
            return image
        }
        // ImageIO can't thumbnail, or even decode, some TIFF-based files: RAW photos, including
        // ones imported from other cameras. Try, in order: the system RAW pipeline, any image
        // in the file ImageIO can decode, and finally the preview embedded in the file.
        return rawImage(from: data, maxPixelSize: maxPixelSize)
            ?? scaledImage(from: source, maxPixelSize: maxPixelSize)
            ?? embeddedPreview(from: source, maxPixelSize: maxPixelSize)
    }

    /// Develops a RAW file with Core Image, at a reduced size. `nil` when the data isn't RAW or
    /// the camera's format isn't supported.
    static func rawImage(from data: Data, maxPixelSize: Int) -> CGImage? {
        guard let filter = CIRAWFilter(imageData: data, identifierHint: nil) else {
            return nil
        }
        let longEdge = max(filter.nativeSize.width, filter.nativeSize.height)
        if longEdge > 0 {
            filter.scaleFactor = Float(min(1, Double(maxPixelSize) / longEdge))
        }
        guard let output = filter.outputImage, !output.extent.isInfinite, !output.extent.isEmpty,
            let image = CIContext().createCGImage(output, from: output.extent)
        else {
            return nil
        }
        // The filter applies the file's orientation, and its scale is only approximate.
        return draw(image, orientation: 1, maxPixelSize: maxPixelSize)
    }

    /// The preview a file carries alongside its main image. It can be much smaller than
    /// `maxPixelSize`, so it is the last resort.
    static func embeddedPreview(from source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options =
            [
                kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    /// The slow path: decodes the largest image in the file that ImageIO can read (a RAW file
    /// can hold a full-size rendering next to the sensor data), then draws it upright at the
    /// reduced size. Uses far more memory than `CGImageSourceCreateThumbnailAtIndex`.
    static func scaledImage(from source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        var best: (image: CGImage, index: Int)?
        for index in 0..<CGImageSourceGetCount(source) {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                continue
            }
            if best.map({ image.width * image.height > $0.image.width * $0.image.height }) ?? true {
                best = (image, index)
            }
        }
        guard let best else {
            return nil
        }
        let properties =
            CGImageSourceCopyPropertiesAtIndex(source, best.index, nil) as? [CFString: Any]
        let orientation = properties?[kCGImagePropertyOrientation] as? Int ?? 1
        return draw(best.image, orientation: orientation, maxPixelSize: maxPixelSize)
    }

    /// Draws `image` upright for the given EXIF orientation, no larger than `maxPixelSize` on
    /// its long edge and never upscaled.
    static func draw(_ image: CGImage, orientation: Int, maxPixelSize: Int) -> CGImage? {
        let longEdge = max(image.width, image.height)
        let scale = min(1, Double(maxPixelSize) / Double(longEdge))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        // Orientations 5–8 turn the image on its side.
        let isSideways = (5...8).contains(orientation)
        guard
            let context = CGContext(
                data: nil,
                width: isSideways ? height : width,
                height: isSideways ? width : height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else {
            return nil
        }
        // Transparent pixels would otherwise come out black in a JPEG.
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))

        // Core Graphics' origin is bottom-left; each case maps the stored image upright.
        let drawnWidth = Double(width)
        let drawnHeight = Double(height)
        switch orientation {
        case 2:
            context.translateBy(x: drawnWidth, y: 0)
            context.scaleBy(x: -1, y: 1)
        case 3:
            context.translateBy(x: drawnWidth, y: drawnHeight)
            context.rotate(by: .pi)
        case 4:
            context.translateBy(x: 0, y: drawnHeight)
            context.scaleBy(x: 1, y: -1)
        case 5:
            context.translateBy(x: drawnHeight, y: drawnWidth)
            context.scaleBy(x: 1, y: -1)
            context.rotate(by: .pi / 2)
        case 6:
            context.translateBy(x: 0, y: drawnWidth)
            context.rotate(by: -.pi / 2)
        case 7:
            context.scaleBy(x: 1, y: -1)
            context.rotate(by: -.pi / 2)
        case 8:
            context.translateBy(x: drawnHeight, y: 0)
            context.rotate(by: .pi / 2)
        default:
            break
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: drawnWidth, height: drawnHeight))
        return context.makeImage()
    }

    /// The same, decoded off the caller's actor.
    @concurrent
    static func decode(_ data: Data, maxPixelSize: Int) async -> CGImage? {
        cgImage(from: data, maxPixelSize: maxPixelSize)
    }
}
