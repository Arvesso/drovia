import CoreGraphics
import CoreText
import Foundation

struct RGBA: Equatable, Hashable, Sendable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat = 1

    init(_ hex: UInt32, alpha: CGFloat = 1) {
        red = CGFloat((hex >> 16) & 0xFF) / 255
        green = CGFloat((hex >> 8) & 0xFF) / 255
        blue = CGFloat(hex & 0xFF) / 255
        self.alpha = alpha
    }

    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    func withAlpha(_ alpha: CGFloat) -> RGBA {
        var copy = self
        copy.alpha = alpha
        return copy
    }

    /// Black or white, whichever reads better on top of this color.
    var contrasting: RGBA {
        0.299 * red + 0.587 * green + 0.114 * blue > 0.6 ? RGBA(0x000000) : RGBA(0xFFFFFF)
    }

    static let palette: [RGBA] = [
        RGBA(0xFF3B30), RGBA(0xFF9500), RGBA(0xFFCC00), RGBA(0x34C759), RGBA(0x0A84FF), RGBA(0xAF52DE),
        RGBA(0x000000), RGBA(0xFFFFFF),
    ]
}

enum AnnotationTool: String, CaseIterable, Identifiable, Sendable {
    case arrow, rectangle, ellipse, highlight, pen, text, redact

    var id: Self {
        self
    }

    var symbol: String {
        switch self {
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .highlight: "highlighter"
        case .pen: "scribble"
        case .text: "textformat"
        case .redact: "eye.slash"
        }
    }

    var title: String {
        switch self {
        case .arrow: String(localized: "Arrow")
        case .rectangle: String(localized: "Rectangle")
        case .ellipse: String(localized: "Ellipse")
        case .highlight: String(localized: "Highlight")
        case .pen: String(localized: "Pen")
        case .text: String(localized: "Text")
        case .redact: String(localized: "Redact")
        }
    }
}

/// A mark drawn over an image. Geometry is in image pixels, origin at the top left.
struct Annotation: Equatable, Hashable, Sendable {
    enum Shape: Equatable, Hashable, Sendable {
        case arrow(from: CGPoint, to: CGPoint)
        case rectangle(CGRect)
        case ellipse(CGRect)
        case highlight(CGRect)
        case pen([CGPoint])
        case text(String, at: CGPoint)
        case redact(CGRect)
    }

    var shape: Shape
    var color: RGBA
    var lineWidth: CGFloat
    var fontSize: CGFloat

    var isRedaction: Bool {
        if case .redact = shape {
            return true
        }
        return false
    }

    /// Too small to be intentional (a click rather than a drag).
    var isNegligible: Bool {
        switch shape {
        case let .arrow(from, to): hypot(to.x - from.x, to.y - from.y) < lineWidth * 2
        case let .rectangle(rect), let .ellipse(rect), let .highlight(rect), let .redact(rect):
            rect.width < 4 || rect.height < 4
        case let .pen(points): points.count < 2
        case let .text(text, _): text.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
}

/// Draws annotations into a context whose coordinates are image pixels with a top-left origin.
enum AnnotationDrawer {
    /// - Parameters:
    ///   - source: The image being annotated, possibly downscaled by `sourceScale` (for live previews);
    ///     redactions sample it.
    static func draw(
        _ annotations: [Annotation], source: CGImage, sourceScale: CGFloat, redaction: RedactionStyle,
        in context: CGContext
    ) {
        // Redactions change the picture itself, so they go below every other mark.
        for annotation in annotations where annotation.isRedaction {
            draw(annotation, source: source, sourceScale: sourceScale, redaction: redaction, in: context)
        }
        for annotation in annotations where !annotation.isRedaction {
            draw(annotation, source: source, sourceScale: sourceScale, redaction: redaction, in: context)
        }
    }

    private static func draw(
        _ annotation: Annotation, source: CGImage, sourceScale: CGFloat, redaction: RedactionStyle,
        in context: CGContext
    ) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(annotation.color.cgColor)
        context.setFillColor(annotation.color.cgColor)
        context.setLineWidth(annotation.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch annotation.shape {
        case let .arrow(from, to):
            drawArrow(from: from, to: to, width: annotation.lineWidth, in: context)
        case let .rectangle(rect):
            let radius = min(annotation.lineWidth * 1.5, rect.width / 2, rect.height / 2)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.strokePath()
        case let .ellipse(rect):
            context.strokeEllipse(in: rect)
        case let .highlight(rect):
            context.setBlendMode(.multiply)
            context.setFillColor(annotation.color.withAlpha(0.4).cgColor)
            context.fill(rect)
        case let .pen(points):
            guard let first = points.first else { return }
            context.move(to: first)
            points.dropFirst().forEach { context.addLine(to: $0) }
            context.strokePath()
        case let .text(text, origin):
            drawText(text, at: origin, size: annotation.fontSize, color: annotation.color, in: context)
        case let .redact(rect):
            drawRedaction(rect, source: source, sourceScale: sourceScale, style: redaction, in: context)
        }
    }

    private static func drawArrow(from start: CGPoint, to end: CGPoint, width: CGFloat, in context: CGContext) {
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > 0 else { return }
        let direction = CGPoint(x: (end.x - start.x) / length, y: (end.y - start.y) / length)
        let headLength = min(width * 4 + 8, length * 0.6)
        let headHalfWidth = headLength * 0.6
        let base = CGPoint(x: end.x - direction.x * headLength, y: end.y - direction.y * headLength)
        let normal = CGPoint(x: -direction.y, y: direction.x)

        context.move(to: start)
        context.addLine(to: CGPoint(
            x: base.x + direction.x * headLength * 0.3,
            y: base.y + direction.y * headLength * 0.3
        ))
        context.strokePath()

        context.move(to: end)
        context.addLine(to: CGPoint(x: base.x + normal.x * headHalfWidth, y: base.y + normal.y * headHalfWidth))
        context.addLine(to: CGPoint(x: base.x - normal.x * headHalfWidth, y: base.y - normal.y * headHalfWidth))
        context.closePath()
        context.fillPath()
    }

    /// Bold text with a contrasting outline so it reads on any background. `origin` is the top-left corner.
    private static func drawText(
        _ text: String,
        at origin: CGPoint,
        size: CGFloat,
        color: RGBA,
        in context: CGContext
    ) {
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
            NSAttributedString.Key(kCTStrokeColorAttributeName as String): color.contrasting.withAlpha(0.85).cgColor,
            // Negative stroke width means fill and outline.
            NSAttributedString.Key(kCTStrokeWidthAttributeName as String): -4,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let ascent = CTFontGetAscent(font)
        // Core Text draws with y up; flip locally around the baseline.
        context.translateBy(x: origin.x, y: origin.y + ascent)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
    }

    private static func drawRedaction(
        _ rect: CGRect, source: CGImage, sourceScale: CGFloat, style: RedactionStyle, in context: CGContext
    ) {
        // Only the part over the image: the piece cut from it would otherwise be stretched over the whole rect.
        let imageBounds = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(source.width) / sourceScale,
            height: CGFloat(source.height) / sourceScale
        )
        let rect = rect.intersection(imageBounds)
        guard !rect.isEmpty else { return }
        let sampled = CGRect(
            x: rect.minX * sourceScale,
            y: rect.minY * sourceScale,
            width: rect.width * sourceScale,
            height: rect.height * sourceScale
        ).integral
        guard style != .blackBox, let piece = source.cropping(to: sampled),
              let covered = try? VisionEngine.redact(
                  piece,
                  regions: [CGRect(x: 0, y: 0, width: piece.width, height: piece.height)],
                  style: style,
                  pixelScale: sourceScale
              )
        else {
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(rect)
            return
        }
        drawImage(covered, in: rect, context: context)
    }

    /// Draws an image right side up into a top-left-origin context.
    static func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }
}
