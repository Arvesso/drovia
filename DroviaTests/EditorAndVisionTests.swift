import AppKit
@testable import Drovia
import Testing

/// Solid-color test images and pixel probes. Pixel coordinates have the origin at the top left.
enum TestImages {
    static func solid(_ color: RGBA, width: Int = 200, height: Int = 100) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    /// Black text on white, large enough for OCR, one line per string.
    static func text(_ lines: String...) throws -> CGImage {
        let lineHeight: CGFloat = 100
        let size = CGSize(width: 1400, height: 100 + lineHeight * CGFloat(lines.count))
        let image = NSImage(size: size, flipped: true) { rect in
            NSColor.white.setFill()
            rect.fill()
            for (index, line) in lines.enumerated() {
                NSAttributedString(string: line, attributes: [
                    .font: NSFont.systemFont(ofSize: 56), .foregroundColor: NSColor.black,
                ]).draw(at: NSPoint(x: 40, y: 50 + lineHeight * CGFloat(index)))
            }
            return true
        }
        return try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }

    static func pixel(
        _ image: CGImage,
        x: Int,
        y: Int
    ) throws -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        var data = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (data[0], data[1], data[2], data[3])
    }
}

struct EditorRendererTests {
    private let size = CGSize(width: 200, height: 100)

    @Test func cropsToRect() throws {
        let image = try TestImages.solid(RGBA(0xFF0000))
        let output = try EditorRenderer.render(
            source: image, imageSize: size, crop: CGRect(x: 10, y: 20, width: 50, height: 30),
            annotations: [], background: nil, redaction: .blackBox
        )
        #expect(output.width == 50 && output.height == 30)
    }

    @Test func drawsAnnotationsRelativeToCrop() throws {
        let image = try TestImages.solid(RGBA(0xFFFFFF))
        // A black box at (60, 40) in the original lands at (10, 10) after cropping from (50, 30).
        let box = Annotation(
            shape: .redact(CGRect(x: 60, y: 40, width: 20, height: 20)),
            color: RGBA(0xFF0000),
            lineWidth: 4,
            fontSize: 20
        )
        let output = try EditorRenderer.render(
            source: image, imageSize: size, crop: CGRect(x: 50, y: 30, width: 100, height: 60),
            annotations: [box], background: nil, redaction: .blackBox
        )
        #expect(try TestImages.pixel(output, x: 20, y: 20).red == 0)
        #expect(try TestImages.pixel(output, x: 5, y: 5).red == 255)
    }

    @Test func backgroundAddsPaddingAndAspect() throws {
        let image = try TestImages.solid(RGBA(0x0000FF))
        var style = BackgroundStyle(fill: .solid(RGBA(0xFFFFFF)), padding: 0.1, cornerRadius: 0, shadow: 0)
        var output = try EditorRenderer.render(
            source: image, imageSize: size, crop: CGRect(origin: .zero, size: size),
            annotations: [], background: style, redaction: .blackBox
        )
        #expect(output.width == 240 && output.height == 140)
        #expect(try TestImages.pixel(output, x: 5, y: 5).blue == 255 && TestImages.pixel(output, x: 5, y: 5).red == 255)
        #expect(try TestImages.pixel(output, x: 120, y: 70).red == 0)

        style.aspect = .square
        output = try EditorRenderer.render(
            source: image, imageSize: size, crop: CGRect(origin: .zero, size: size),
            annotations: [], background: style, redaction: .blackBox
        )
        #expect(output.width == output.height)
    }

    @Test func transparentBackgroundKeepsAlpha() throws {
        let image = try TestImages.solid(RGBA(0x00FF00))
        let style = BackgroundStyle(fill: .none, padding: 0.1, cornerRadius: 0.05, shadow: 0)
        let output = try EditorRenderer.render(
            source: image, imageSize: size, crop: CGRect(origin: .zero, size: size),
            annotations: [], background: style, redaction: .blackBox
        )
        #expect(output.hasAlpha)
        #expect(try TestImages.pixel(output, x: 2, y: 2).alpha == 0)
    }

    @Test func previewScaleShrinksOutput() throws {
        let image = try TestImages.solid(RGBA(0xFFFFFF))
        let output = try EditorRenderer.render(
            source: image, imageSize: size, crop: CGRect(origin: .zero, size: size),
            annotations: [], background: nil, redaction: .blackBox, outputScale: 0.5
        )
        #expect(output.width == 100 && output.height == 50)
    }

    @Test func clicksAreNegligible() {
        let click = Annotation(
            shape: .rectangle(CGRect(x: 0, y: 0, width: 1, height: 1)),
            color: RGBA(0),
            lineWidth: 4,
            fontSize: 20
        )
        let arrow = Annotation(
            shape: .arrow(from: .zero, to: CGPoint(x: 50, y: 0)),
            color: RGBA(0),
            lineWidth: 4,
            fontSize: 20
        )
        #expect(click.isNegligible)
        #expect(!arrow.isNegligible)
    }
}

struct VisionEngineTests {
    @Test func findsSensitiveText() {
        let text = "Mail me at anna@example.com or call +1 415 555 0132, card 4111 1111 1111 1111"
        let found = VisionEngine.sensitiveRanges(in: text).map { String(text[$0]) }
        #expect(found.contains { $0.contains("anna@example.com") })
        #expect(found.contains { $0.contains("555") })
        #expect(found.contains { $0.contains("4111 1111 1111 1111") })
        #expect(VisionEngine.sensitiveRanges(in: "Meeting at 10, room 4").isEmpty)
    }

    @Test func convertsVisionRects() {
        let rect = VisionEngine.pixelRect(
            CGRect(x: 0.5, y: 0, width: 0.5, height: 0.25),
            in: CGSize(width: 200, height: 100)
        )
        #expect(rect == CGRect(x: 100, y: 75, width: 100, height: 25))
    }

    @Test func blackBoxCoversRegion() throws {
        let image = try TestImages.solid(RGBA(0xFFFFFF))
        let output = try VisionEngine.redact(
            image,
            regions: [CGRect(x: 0, y: 0, width: 50, height: 50)],
            style: .blackBox
        )
        #expect(try TestImages.pixel(output, x: 10, y: 10).red == 0)
        #expect(try TestImages.pixel(output, x: 100, y: 80).red == 255)
    }

    @Test func recognizesAndLocatesEmail() throws {
        let image = try TestImages.text("Contact: anna@example.com")
        #expect(try VisionEngine.text(in: image).contains("anna@example.com"))
        let regions = try VisionEngine.sensitiveRegions(in: image, targets: .personalText)
        #expect(regions.count == 1)
        // The email sits on the right part of the line, not over "Contact:".
        #expect((regions.first?.minX ?? 0) > 200)
    }

    @Test func findsCardNumberWrappedOntoNextLine() throws {
        let image = try TestImages.text("Card 4111 1111", "1111 1111")
        let regions = try VisionEngine.sensitiveRegions(in: image, targets: .personalText)
        // Both halves are covered: one region on each line.
        let middle = CGFloat(image.height) / 2
        #expect(regions.contains { $0.midY < middle })
        #expect(regions.contains { $0.midY > middle })
    }
}
