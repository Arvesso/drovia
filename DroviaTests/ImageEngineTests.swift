import CoreGraphics
@testable import Drovia
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

struct ImageEngineTests {
    private let folder: TemporaryFolder

    init() throws {
        folder = try TemporaryFolder()
    }

    // MARK: Fixtures

    /// A 400×200 image with a red left half, saved with GPS and EXIF metadata and the given orientation.
    private func fixture(
        _ name: String,
        type: UTType = .jpeg,
        orientation: CGImagePropertyOrientation = .up,
        alpha: Bool = false
    ) throws -> URL {
        let context = try #require(CGContext(
            data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: alpha ? 0.5 : 1))
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        let image = try #require(context.makeImage())

        let url = folder.url.appendingPathComponent(name)
        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL,
            type.identifier as CFString,
            1,
            nil
        ))
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation.rawValue,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 55.75, kCGImagePropertyGPSLatitudeRef: "N"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "secret"],
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    private func info(_ url: URL) throws -> (type: String, width: Int, height: Int, properties: [CFString: Any]) {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return (
            CGImageSourceGetType(source) as String? ?? "",
            properties[kCGImagePropertyPixelWidth] as? Int ?? 0,
            properties[kCGImagePropertyPixelHeight] as? Int ?? 0,
            properties
        )
    }

    // MARK: Convert

    @Test(arguments: ImageFormat.convertTargets.filter { $0 != .pdf && $0 != .icns })
    func convertsToFormat(_ format: ImageFormat) throws {
        let source = try fixture("source.png", type: .png, alpha: true)
        let output = folder.url.appendingPathComponent("out.\(format.fileExtension)")
        try ImageEngine.write(source, as: format, to: output, options: ImageWriteOptions())
        let result = try info(output)
        #expect(result.type == format.utType.identifier)
        #expect(result.width == 400 && result.height == 200)
    }

    @Test func convertsToPDFAndICNS() throws {
        let source = try fixture("source.png", type: .png)
        for format in [ImageFormat.pdf, .icns] {
            let output = folder.url.appendingPathComponent("out.\(format.fileExtension)")
            try ImageEngine.write(source, as: format, to: output, options: ImageWriteOptions())
            #expect((output.fileSize ?? 0) > 0)
        }
    }

    @Test func conversionAppliesOrientationToPixels() throws {
        let source = try fixture("rotated.jpg", orientation: .right)
        let output = folder.url.appendingPathComponent("out.png")
        try ImageEngine.write(source, as: .png, to: output, options: ImageWriteOptions())
        let result = try info(output)
        #expect(result.width == 200 && result.height == 400)
        #expect((result.properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
    }

    @Test func downscalesToMaxPixelSize() throws {
        let source = try fixture("big.jpg")
        let output = folder.url.appendingPathComponent("small.jpg")
        try ImageEngine.write(source, as: .jpeg, to: output, options: ImageWriteOptions(maxPixelSize: 100))
        let result = try info(output)
        #expect(result.width == 100 && result.height == 50)
    }

    // MARK: Metadata

    @Test func removesAllMetadataButKeepsOrientation() throws {
        let source = try fixture("meta.jpg", orientation: .right)
        let output = folder.url.appendingPathComponent("clean.jpg")
        try ImageEngine.removeMetadata(source, to: output, mode: .all, format: .jpeg)
        let result = try info(output)
        #expect(result.properties[kCGImagePropertyGPSDictionary] == nil)
        let exif = result.properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifUserComment] == nil)
        #expect(result.properties[kCGImagePropertyOrientation] as? Int == 6)
    }

    @Test func removesOnlyLocation() throws {
        let source = try fixture("meta.jpg")
        let output = folder.url.appendingPathComponent("noloc.jpg")
        try ImageEngine.removeMetadata(source, to: output, mode: .location, format: .jpeg)
        let result = try info(output)
        #expect(result.properties[kCGImagePropertyGPSDictionary] == nil)
        let exif = result.properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifUserComment] as? String == "secret")
    }

    // MARK: Rotate

    @Test func rotatesJPEGByOrientationTag() throws {
        let source = try fixture("photo.jpg")
        let output = folder.url.appendingPathComponent("rotated.jpg")
        try ImageEngine.rotateClockwise(source, to: output, format: .jpeg)
        let result = try info(output)
        #expect(result.properties[kCGImagePropertyOrientation] as? Int == 6)
        #expect(result.width == 400) // pixels untouched
    }

    @Test func rotatesPNGPixels() throws {
        let source = try fixture("shot.png", type: .png)
        let output = folder.url.appendingPathComponent("rotated.png")
        try ImageEngine.rotateClockwise(source, to: output, format: .png)
        let result = try info(output)
        #expect(result.width == 200 && result.height == 400)
        // The red left half ends up on top after a clockwise turn.
        let imageSource = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        #expect(try pixel(image, x: 100, y: 50).red > 200)
        #expect(try pixel(image, x: 100, y: 350).blue > 200)
    }

    @Test func orientationRotationCycles() {
        var orientation = CGImagePropertyOrientation.upMirrored
        for _ in 0 ..< 4 {
            orientation = orientation.rotatedClockwise
        }
        #expect(orientation == .upMirrored)
        #expect(CGImagePropertyOrientation.up.rotatedClockwise == .right)
    }

    /// The displayed image for `orientation.rotatedClockwise` is the one for `orientation`, turned clockwise.
    @Test(arguments: (1 ... 8).compactMap { CGImagePropertyOrientation(rawValue: UInt32($0)) })
    func rotatedOrientationTurnsDisplayedImageClockwise(_ orientation: CGImagePropertyOrientation) throws {
        let shown = try displayedGrid(orientation)
        // Turning clockwise: the new first row is the old first column, read bottom to top.
        let turned = shown[0].indices.map { column in shown.indices.reversed().map { shown[$0][column] } }
        #expect(try displayedGrid(orientation.rotatedClockwise) == turned)
    }

    /// Red values of a 3×2 grid of 20 px blocks, each a distinct shade, as shown with `orientation` applied.
    private func displayedGrid(_ orientation: CGImagePropertyOrientation) throws -> [[UInt8]] {
        let block = 20, columns = 3, rows = 2
        let context = try #require(CGContext(
            data: nil, width: columns * block, height: rows * block, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        for row in 0 ..< rows {
            for column in 0 ..< columns {
                context.setFillColor(
                    red: CGFloat(40 + (row * columns + column) * 30) / 255,
                    green: 0,
                    blue: 0,
                    alpha: 1
                )
                // Context y points up; row 0 is the top.
                context.fill(CGRect(x: column * block, y: (rows - 1 - row) * block, width: block, height: block))
            }
        }
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            data,
            UTType.tiff.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImagePropertyOrientation: orientation.rawValue] as CFDictionary
        )
        #expect(CGImageDestinationFinalize(destination))
        let source = try #require(CGImageSourceCreateWithData(data, nil))
        let shown = try #require(CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: columns * block,
        ] as CFDictionary))
        // Sample block centers, which interpolation at block edges can't touch.
        return try (0 ..< shown.height / block).map { row in
            try (0 ..< shown.width / block).map { column in
                try pixel(shown, x: column * block + block / 2, y: row * block + block / 2).red
            }
        }
    }

    @Test func heifFilesAreWrittenAsHEIC() throws {
        #expect(try ImageFormat(type: #require(UTType(filenameExtension: "heif"))) == .heic)
    }

    /// RGBA of a pixel, with y measured from the top.
    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> (red: UInt8, blue: UInt8) {
        var data = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (data[0], data[2])
    }
}
