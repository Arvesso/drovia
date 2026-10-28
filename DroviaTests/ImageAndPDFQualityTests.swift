import AppKit
@testable import Drovia
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers

/// What re-encoding keeps: frames, color, depth, resolution, and what "remove location" removes.
struct ImageAndPDFQualityTests {
    private let folder: TemporaryFolder

    init() throws {
        folder = try TemporaryFolder()
    }

    private func image(
        width: Int = 40, height: Int = 20, bits: Int = 8, space: CFString = CGColorSpace.sRGB
    ) throws -> CGImage {
        let colorSpace = try #require(CGColorSpace(name: space))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: bits, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        return try #require(context.makeImage())
    }

    /// Writes `frames` images (each with `properties`) as one file of `type`.
    private func write(
        _ name: String, type: UTType, frames: Int = 1, image: CGImage? = nil, properties: [CFString: Any] = [:]
    ) throws -> URL {
        let url = folder.url.appendingPathComponent(name)
        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL,
            type.identifier as CFString,
            frames,
            nil
        ))
        for _ in 0 ..< frames {
            try CGImageDestinationAddImage(destination, image ?? self.image(), properties as CFDictionary)
        }
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    private func properties(_ url: URL) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    @Test func animatedImageIsNotSilentlyFlattened() throws {
        let gif = try write("anim.gif", type: .gif, frames: 3)
        #expect(throws: ImageEngineError.self) {
            try ImageEngine.write(gif, as: .webp, to: folder.url.appendingPathComponent("anim.webp"), options: .init())
        }
    }

    @Test func multiPageTIFFBecomesMultiPagePDF() throws {
        let tiff = try write("scan.tiff", type: .tiff, frames: 3)
        let pdf = folder.url.appendingPathComponent("scan.pdf")
        try ImageEngine.write(tiff, as: .pdf, to: pdf, options: .init())
        #expect(PDFDocument(url: pdf)?.pageCount == 3)
    }

    @Test func tiffIsCompressed() throws {
        let output = folder.url.appendingPathComponent("out.tiff")
        try ImageEngine.write(write("in.png", type: .png), as: .tiff, to: output, options: .init())
        let tiff = try #require(properties(output)[kCGImagePropertyTIFFDictionary] as? [CFString: Any])
        #expect(tiff[kCGImagePropertyTIFFCompression] as? Int == 5)
    }

    @Test func turningKeepsWideGamutAndDepth() throws {
        // PNG has no orientation tag, so turning redraws the pixels.
        let source = try write("p3.png", type: .png, image: image(bits: 16, space: CGColorSpace.displayP3))
        let output = folder.url.appendingPathComponent("turned.png")
        try ImageEngine.rotateClockwise(source, to: output, format: .png)
        let turned = try ImageEngine.loadImage(output)
        #expect(turned.bitsPerComponent == 16)
        #expect(turned.colorSpace?.name == CGColorSpace.displayP3)
    }

    @Test func convertingKeepsResolution() throws {
        let source = try write("retina.png", type: .png, properties: [
            kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144,
        ])
        let output = folder.url.appendingPathComponent("retina.jpg")
        try ImageEngine.write(source, as: .jpeg, to: output, options: .init())
        #expect(try properties(output)[kCGImagePropertyDPIWidth] as? Int == 144)
    }

    @Test func removingLocationRemovesPlaceNames() throws {
        let source = try write("trip.jpg", type: .jpeg, properties: [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 55.75, kCGImagePropertyGPSLatitudeRef: "N"],
            kCGImagePropertyIPTCDictionary: [
                kCGImagePropertyIPTCCity: "Moscow",
                kCGImagePropertyIPTCCaptionAbstract: "Hi",
            ],
        ])
        let output = folder.url.appendingPathComponent("clean.jpg")
        try ImageEngine.removeMetadata(source, to: output, mode: .location, format: .jpeg)
        let result = try properties(output)
        #expect(result[kCGImagePropertyGPSDictionary] == nil)
        let iptc = result[kCGImagePropertyIPTCDictionary] as? [CFString: Any]
        #expect(iptc?[kCGImagePropertyIPTCCity] == nil)
        // Not location: kept.
        #expect(iptc?[kCGImagePropertyIPTCCaptionAbstract] as? String == "Hi")
    }

    @Test(arguments: [true, false])
    func webpKeepsMetadataOnlyWhenAsked(_ keepsMetadata: Bool) throws {
        let source = try write("photo.png", type: .png, properties: [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2024:05:01 10:00:00"],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 55.75, kCGImagePropertyGPSLatitudeRef: "N"],
        ])
        let output = folder.url.appendingPathComponent("photo.webp")
        try ImageEngine.write(source, as: .webp, to: output, options: .init(keepsMetadata: keepsMetadata))
        let exif = try properties(output)[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let date = exif?[kCGImagePropertyExifDateTimeOriginal] as? String
        #expect(date == (keepsMetadata ? "2024:05:01 10:00:00" : nil))
    }

    @Test func webpKeepsWideGamut() throws {
        let source = try write("p3.png", type: .png, image: image(space: CGColorSpace.displayP3))
        let output = folder.url.appendingPathComponent("p3.webp")
        try ImageEngine.write(source, as: .webp, to: output, options: .init())
        #expect(try ImageEngine.loadImage(output).colorSpace?.name == CGColorSpace.displayP3)
    }

    @Test func mergedPhotoGetsAPageSizedPage() throws {
        let photo = try write("photo.jpg", type: .jpeg, image: image(width: 4000, height: 3000))
        let pdf = folder.url.appendingPathComponent("merged.pdf")
        try PDFEngine.merge([photo, photo], to: pdf)
        let page = try #require(PDFDocument(url: pdf)?.page(at: 0)?.bounds(for: .mediaBox).size)
        // A4 landscape, not 4000 × 3000 points.
        #expect(page == CGSize(width: 842, height: 595))
    }

    @Test func removingMetadataRemovesCommentAuthors() throws {
        let document = PDFDocument()
        let page = PDFPage()
        let note = PDFAnnotation(
            bounds: CGRect(x: 10, y: 10, width: 20, height: 20),
            forType: .text,
            withProperties: nil
        )
        note.userName = "Anna Reviewer"
        page.addAnnotation(note)
        document.insert(page, at: 0)
        let source = folder.url.appendingPathComponent("reviewed.pdf")
        #expect(document.write(to: source))

        let output = folder.url.appendingPathComponent("clean.pdf")
        try PDFEngine.removeMetadata(source, to: output)
        let annotations = try #require(PDFDocument(url: output)?.page(at: 0)?.annotations)
        #expect(!annotations.isEmpty)
        #expect(annotations.allSatisfy { $0.userName == nil })
    }
}
