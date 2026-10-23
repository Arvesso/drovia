import CoreGraphics
import Foundation

enum BackgroundFill: Equatable, Hashable, Sendable {
    case none
    case gradient(Int)
    case solid(RGBA)

    static let gradients: [(RGBA, RGBA)] = [
        (RGBA(0x8B93F8), RGBA(0xF28FB0)),
        (RGBA(0x3AA0FF), RGBA(0x22D3C5)),
        (RGBA(0xFF8A3D), RGBA(0xF4416C)),
        (RGBA(0x38B26B), RGBA(0xA6E36B)),
        (RGBA(0x2B2E45), RGBA(0x5A5F96)),
        (RGBA(0xF1F1F5), RGBA(0xD4D4DE)),
    ]

    static let presets: [BackgroundFill] = gradients.indices.map(BackgroundFill.gradient)
        + [.solid(RGBA(0xFFFFFF)), .solid(RGBA(0x000000)), .none]
}

enum BackgroundAspect: String, CaseIterable, Identifiable, Sendable {
    case auto, square, standard, wide

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .auto: String(localized: "Auto")
        case .square: "1:1"
        case .standard: "4:3"
        case .wide: "16:9"
        }
    }

    var ratio: CGFloat? {
        switch self {
        case .auto: nil
        case .square: 1
        case .standard: 4 / 3
        case .wide: 16 / 9
        }
    }
}

/// A frame around the image: padding, fill, rounded corners and a shadow.
struct BackgroundStyle: Equatable, Hashable, Sendable {
    var fill = BackgroundFill.gradient(0)
    /// Padding as a fraction of the image's longer side.
    var padding = 0.08
    /// Corner radius as a fraction of the image's shorter side.
    var cornerRadius = 0.025
    /// 0...1
    var shadow = 0.6
    var aspect = BackgroundAspect.auto
}

/// Produces the edited image: crop, then annotations, then the optional background frame.
enum EditorRenderer {
    /// - Parameters:
    ///   - source: The original image, or a downscaled copy for previews.
    ///   - imageSize: Size of the original image; `crop` and annotations are in its pixels.
    ///   - outputScale: Output pixels per original pixel (1 for saving, less for previews).
    static func render(
        source: CGImage,
        imageSize: CGSize,
        crop: CGRect,
        annotations: [Annotation],
        background: BackgroundStyle?,
        redaction: RedactionStyle,
        outputScale: CGFloat = 1
    ) throws -> CGImage {
        let crop = crop.integral.intersection(CGRect(origin: .zero, size: imageSize))
        let layout = layout(content: crop.size, background: background)
        let opaque = background.map { $0.fill != .none } ?? !source.hasAlpha
        let width = max(1, Int((layout.canvas.width * outputScale).rounded()))
        let height = max(1, Int((layout.canvas.height * outputScale).rounded()))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ImageEngineError.cannotWrite(.png)
        }
        context.interpolationQuality = .high
        // Work in original-image pixels with the origin at the top left.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: outputScale, y: -outputScale)

        let content = CGRect(origin: layout.contentOrigin, size: crop.size)
        if let background {
            drawBackground(
                background,
                canvas: CGRect(origin: .zero, size: layout.canvas),
                content: content,
                outputScale: outputScale,
                in: context
            )
        }

        context.saveGState()
        if let background, background.cornerRadius > 0 {
            let radius = background.cornerRadius * min(crop.width, crop.height)
            context.addPath(CGPath(roundedRect: content, cornerWidth: radius, cornerHeight: radius, transform: nil))
        } else {
            context.addRect(content)
        }
        context.clip()
        context.translateBy(x: content.minX - crop.minX, y: content.minY - crop.minY)
        AnnotationDrawer.drawImage(source, in: CGRect(origin: .zero, size: imageSize), context: context)
        AnnotationDrawer.draw(
            annotations, source: source, sourceScale: CGFloat(source.width) / imageSize.width,
            redaction: redaction, in: context
        )
        context.restoreGState()

        return try context.makeImage().orThrow(ImageEngineError.cannotWrite(.png))
    }

    /// Canvas size and where the cropped image sits on it.
    static func layout(content: CGSize, background: BackgroundStyle?) -> (canvas: CGSize, contentOrigin: CGPoint) {
        guard let background else { return (content, .zero) }
        let padding = (background.padding * max(content.width, content.height)).rounded()
        var canvas = CGSize(width: content.width + padding * 2, height: content.height + padding * 2)
        if let ratio = background.aspect.ratio {
            if canvas.width / canvas.height < ratio {
                canvas.width = (canvas.height * ratio).rounded()
            } else {
                canvas.height = (canvas.width / ratio).rounded()
            }
        }
        let origin = CGPoint(
            x: ((canvas.width - content.width) / 2).rounded(),
            y: ((canvas.height - content.height) / 2).rounded()
        )
        return (canvas, origin)
    }

    private static func drawBackground(
        _ style: BackgroundStyle, canvas: CGRect, content: CGRect, outputScale: CGFloat, in context: CGContext
    ) {
        switch style.fill {
        case .none:
            break
        case let .solid(color):
            context.setFillColor(color.cgColor)
            context.fill(canvas)
        case let .gradient(index):
            let colors = BackgroundFill.gradients[index % BackgroundFill.gradients.count]
            let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: [colors.0.cgColor, colors.1.cgColor] as CFArray,
                locations: [0, 1]
            )!
            context.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: canvas.maxX, y: canvas.maxY),
                options: []
            )
        }

        guard style.shadow > 0 else { return }
        // Shadow offsets ignore the transform, so they're in output pixels with y pointing up.
        let size = max(content.width, content.height) * outputScale
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -size * 0.012 * style.shadow),
            blur: size * 0.04 * style.shadow,
            color: CGColor(gray: 0, alpha: 0.45 * style.shadow)
        )
        let radius = style.cornerRadius * min(content.width, content.height)
        context.addPath(CGPath(roundedRect: content, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fillPath()
        context.restoreGState()
    }
}
