import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Commonplace

/// The real ImageIO processor, run on generated images.
struct ImageProcessorTests {
    private let processor = ImageIOProcessor()

    @Test func landscapeLargerThanTheLimitIsDownscaledToTheLongEdge() async throws {
        let source = try TestImage.data(width: 4000, height: 3000)

        let processed = try await processor.process(source)

        #expect(try TestImage.pixelSize(of: processed.image) == CGSize(width: 3000, height: 2250))
    }

    @Test func portraitLargerThanTheLimitKeepsItsAspect() async throws {
        let source = try TestImage.data(width: 3000, height: 4500)

        let processed = try await processor.process(source)

        #expect(try TestImage.pixelSize(of: processed.image) == CGSize(width: 2000, height: 3000))
    }

    @Test func smallImageIsNotUpscaled() async throws {
        let source = try TestImage.data(width: 640, height: 480)

        let processed = try await processor.process(source)

        #expect(try TestImage.pixelSize(of: processed.image) == CGSize(width: 640, height: 480))
        #expect(try TestImage.pixelSize(of: processed.thumbnail) == CGSize(width: 400, height: 300))
    }

    @Test func tinyImageKeepsItsSizeInBothOutputs() async throws {
        let source = try TestImage.data(width: 120, height: 80)

        let processed = try await processor.process(source)

        #expect(try TestImage.pixelSize(of: processed.image) == CGSize(width: 120, height: 80))
        #expect(try TestImage.pixelSize(of: processed.thumbnail) == CGSize(width: 120, height: 80))
    }

    @Test func thumbnailIsWithinItsLimit() async throws {
        let source = try TestImage.data(width: 4000, height: 3000)

        let processed = try await processor.process(source)

        #expect(try TestImage.pixelSize(of: processed.thumbnail) == CGSize(width: 400, height: 300))
        #expect(processed.thumbnail.count < processed.image.count)
    }

    /// Orientation 6 means the stored pixels are the upright image rotated: the stored top-left
    /// corner belongs at the top-right when displayed.
    @Test func exifOrientationIsBakedIn() async throws {
        let source = try TestImage.data(width: 4000, height: 3000, orientation: 6)

        let processed = try await processor.process(source)

        // Upright, the 4000 × 3000 stored image is 3000 × 4000.
        #expect(try TestImage.pixelSize(of: processed.image) == CGSize(width: 2250, height: 3000))
        #expect(try TestImage.orientation(of: processed.image) == 1)
        // The stored top-left quadrant is red; upright it is the top-right.
        #expect(try TestImage.isRed(processed.image, atUnitX: 0.9, unitY: 0.1))
        #expect(try !TestImage.isRed(processed.image, atUnitX: 0.1, unitY: 0.1))
        #expect(try TestImage.isRed(processed.thumbnail, atUnitX: 0.9, unitY: 0.1))
    }

    @Test func uprightSourceKeepsItsCorners() async throws {
        let source = try TestImage.data(width: 1200, height: 900)

        let processed = try await processor.process(source)

        #expect(try TestImage.isRed(processed.image, atUnitX: 0.1, unitY: 0.1))
        #expect(try !TestImage.isRed(processed.image, atUnitX: 0.9, unitY: 0.1))
    }

    @Test func outputIsJPEGWithoutLocationMetadata() async throws {
        let source = try TestImage.data(width: 1200, height: 900, includeGPS: true)
        #expect(try TestImage.hasGPS(source))

        let processed = try await processor.process(source)

        #expect(try TestImage.typeIdentifier(of: processed.image) == UTType.jpeg.identifier)
        #expect(try TestImage.typeIdentifier(of: processed.thumbnail) == UTType.jpeg.identifier)
        #expect(try !TestImage.hasGPS(processed.image))
    }

    @Test func pngInputIsAccepted() async throws {
        let source = try TestImage.data(width: 1179, height: 2556, type: .png)

        let processed = try await processor.process(source)

        #expect(try TestImage.pixelSize(of: processed.image) == CGSize(width: 1179, height: 2556))
        #expect(try TestImage.typeIdentifier(of: processed.image) == UTType.jpeg.identifier)
    }

    @Test func invalidDataThrows() async {
        await #expect(throws: ImageProcessingError.undecodable) {
            try await processor.process(Data("not an image".utf8))
        }
        await #expect(throws: ImageProcessingError.undecodable) {
            try await processor.process(Data())
        }
    }

    // MARK: Fallback for images ImageIO can't thumbnail

    /// Where the stored top-left corner belongs once the image is upright, per EXIF orientation.
    @Test(arguments: [
        (1, 0.1, 0.1), (2, 0.9, 0.1), (3, 0.9, 0.9), (4, 0.1, 0.9),
        (5, 0.1, 0.1), (6, 0.9, 0.1), (7, 0.9, 0.9), (8, 0.1, 0.9),
    ])
    func fallbackAppliesOrientation(orientation: Int, redX: Double, redY: Double) throws {
        let data = try TestImage.data(width: 800, height: 600, orientation: orientation)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))

        let image = try #require(ImageDownsampler.scaledImage(from: source, maxPixelSize: 400))

        let isSideways = orientation >= 5
        #expect(image.width == (isSideways ? 300 : 400))
        #expect(image.height == (isSideways ? 400 : 300))
        let corners = [(0.1, 0.1), (0.9, 0.1), (0.9, 0.9), (0.1, 0.9)]
        for (x, y) in corners {
            let expected = x == redX && y == redY
            #expect(TestImage.isRed(image, atUnitX: x, unitY: y) == expected)
        }
    }

    /// The fast path and the fallback must agree, whichever one a format ends up on.
    @Test(arguments: 1...8)
    func fallbackMatchesTheThumbnailPath(orientation: Int) throws {
        let data = try TestImage.data(width: 800, height: 600, orientation: orientation)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))

        let fast = try #require(ImageDownsampler.cgImage(from: data, maxPixelSize: 400))
        let slow = try #require(ImageDownsampler.scaledImage(from: source, maxPixelSize: 400))

        #expect(fast.width == slow.width)
        #expect(fast.height == slow.height)
        for (x, y) in [(0.1, 0.1), (0.9, 0.1), (0.9, 0.9), (0.1, 0.9)] {
            #expect(
                TestImage.isRed(fast, atUnitX: x, unitY: y)
                    == TestImage.isRed(slow, atUnitX: x, unitY: y)
            )
        }
    }

    @Test func fallbackDoesNotUpscale() throws {
        let data = try TestImage.data(width: 320, height: 240)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))

        let image = try #require(ImageDownsampler.scaledImage(from: source, maxPixelSize: 3000))

        #expect(image.width == 320)
        #expect(image.height == 240)
    }

    @Test func tiffInputIsAccepted() async throws {
        let source = try TestImage.data(width: 4000, height: 3000, orientation: 6, type: .tiff)

        let processed = try await processor.process(source)

        #expect(try TestImage.pixelSize(of: processed.image) == CGSize(width: 2250, height: 3000))
        #expect(try TestImage.isRed(processed.image, atUnitX: 0.9, unitY: 0.1))
    }

    @Test func limitsAreTheDocumentedValues() {
        #expect(PhotoLimits.imageMaxPixelSize == 3000)
        #expect(PhotoLimits.imageQuality == 0.8)
        #expect(PhotoLimits.thumbnailMaxPixelSize == 400)
        #expect(PhotoLimits.thumbnailQuality == 0.7)
        #expect(PhotoLimits.maxPhotosPerEntry == 20)
    }
}

/// Generated images: white, with the stored top-left quadrant red.
enum TestImage {
    struct Failure: Error {}

    static func data(
        width: Int,
        height: Int,
        orientation: Int? = nil,
        includeGPS: Bool = false,
        type: UTType = .jpeg
    ) throws -> Data {
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else {
            throw Failure()
        }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Core Graphics' origin is bottom-left, so the top-left quadrant has the larger y.
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: height / 2, width: width / 2, height: height - height / 2))
        guard let image = context.makeImage() else {
            throw Failure()
        }

        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
        if let orientation {
            properties[kCGImagePropertyOrientation] = orientation
        }
        if includeGPS {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 34.8697,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 111.761,
                kCGImagePropertyGPSLongitudeRef: "W",
            ]
        }
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, type.identifier as CFString, 1, nil
            )
        else {
            throw Failure()
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw Failure()
        }
        return output as Data
    }

    static func pixelSize(of data: Data) throws -> CGSize {
        let properties = try properties(of: data)
        guard let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            throw Failure()
        }
        return CGSize(width: width, height: height)
    }

    /// The EXIF orientation, where a missing value means upright (1).
    static func orientation(of data: Data) throws -> Int {
        try properties(of: data)[kCGImagePropertyOrientation] as? Int ?? 1
    }

    static func hasGPS(_ data: Data) throws -> Bool {
        try properties(of: data)[kCGImagePropertyGPSDictionary] != nil
    }

    static func typeIdentifier(of data: Data) throws -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let type = CGImageSourceGetType(source)
        else {
            throw Failure()
        }
        return type as String
    }

    /// Samples one pixel of the stored image; `unitY` 0 is the top row.
    static func isRed(_ data: Data, atUnitX unitX: Double, unitY: Double) throws -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw Failure()
        }
        return isRed(image, atUnitX: unitX, unitY: unitY)
    }

    static func isRed(_ image: CGImage, atUnitX unitX: Double, unitY: Double) -> Bool {
        var pixel = [UInt8](repeating: 0, count: 4)
        guard
            let context = CGContext(
                data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else {
            return false
        }
        let x = Double(image.width) * unitX
        let yFromBottom = Double(image.height) * (1 - unitY)
        // Draw the whole image offset so the wanted pixel lands on the 1 × 1 context.
        context.draw(
            image,
            in: CGRect(
                x: -x, y: -yFromBottom, width: Double(image.width), height: Double(image.height))
        )
        return pixel[0] > 200 && pixel[1] < 80 && pixel[2] < 80
    }

    private static func properties(of data: Data) throws -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any]
        else {
            throw Failure()
        }
        return properties
    }
}
