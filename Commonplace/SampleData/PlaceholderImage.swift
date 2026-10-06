import UIKit

/// Generated stand-ins for the user's photos: warm gradients with a ridge line.
///
/// The drawing is resolution-independent, so a thumbnail and a full image made from the same
/// seed show the same picture.
enum PlaceholderImage {
    private static let shapes = [
        CGSize(width: 3, height: 2),
        CGSize(width: 4, height: 3),
        CGSize(width: 3, height: 4),
        CGSize(width: 1, height: 1),
    ]

    static func jpegData(seed: Int, longEdge: CGFloat) -> Data {
        let shape = shapes[abs(seed) % shapes.count]
        let scale = longEdge / max(shape.width, shape.height)
        let size = CGSize(
            width: (shape.width * scale).rounded(),
            height: (shape.height * scale).rounded()
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format)
            .jpegData(withCompressionQuality: 0.8) { rendererContext in
                draw(seed: seed, in: rendererContext.cgContext, size: size)
            }
    }

    private static func draw(seed: Int, in context: CGContext, size: CGSize) {
        var random = Generator(seed: seed)
        let hue = 0.01 + random.next() * 0.1

        let sky = [
            UIColor(hue: hue + 0.06, saturation: 0.3, brightness: 1, alpha: 1).cgColor,
            UIColor(hue: hue, saturation: 0.75, brightness: 0.96, alpha: 1).cgColor,
        ]
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: sky as CFArray,
            locations: [0, 1]
        ) {
            context.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: 0, y: size.height * 0.75),
                options: [.drawsAfterEndLocation]
            )
        }

        let sunRadius = min(size.width, size.height) * 0.09
        let sunCenter = CGPoint(
            x: size.width * (0.2 + random.next() * 0.6),
            y: size.height * (0.3 + random.next() * 0.2)
        )
        context.setFillColor(UIColor(white: 1, alpha: 0.65).cgColor)
        context.fillEllipse(
            in: CGRect(
                x: sunCenter.x - sunRadius,
                y: sunCenter.y - sunRadius,
                width: sunRadius * 2,
                height: sunRadius * 2
            )
        )

        let ridges: [(base: CGFloat, brightness: CGFloat)] = [(0.55, 0.6), (0.72, 0.38)]
        for ridge in ridges {
            let steps = 7
            context.beginPath()
            context.move(to: CGPoint(x: 0, y: size.height))
            for step in 0...steps {
                let x = size.width * CGFloat(step) / CGFloat(steps)
                let y = size.height * (ridge.base + (random.next() - 0.5) * 0.18)
                context.addLine(to: CGPoint(x: x, y: y))
            }
            context.addLine(to: CGPoint(x: size.width, y: size.height))
            context.closePath()
            context.setFillColor(
                UIColor(hue: hue, saturation: 0.85, brightness: ridge.brightness, alpha: 1).cgColor
            )
            context.fillPath()
        }
    }

    /// A small deterministic generator so the same seed always draws the same picture.
    private struct Generator {
        private var state: UInt64

        init(seed: Int) {
            state = UInt64(truncatingIfNeeded: seed) &* 2_654_435_761 &+ 88_172_645_463_325_252
        }

        /// A value in `0..<1`.
        mutating func next() -> CGFloat {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat(state >> 40) / CGFloat(1 << 24)
        }
    }
}
