import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageEngineError: LocalizedError {
    case unreadable(URL)
    case cannotWrite(ImageFormat)
    case tooLarge(ImageFormat, maxSide: Int)

    var errorDescription: String? {
        switch self {
        case let .unreadable(url):
            String(localized: "Can't read \(url.lastPathComponent) as an image")
        case let .cannotWrite(format):
            String(localized: "Can't write \(format.title)")
        case let .tooLarge(format, maxSide):
            String(localized: "\(format.title) images can't be larger than \(maxSide) px")
        }
    }
}

/// Options for writing an image.
struct ImageWriteOptions: Sendable {
    /// 0...1, used by lossy formats.
    var quality = 0.8
    var keepsMetadata = true
    /// Longest side in pixels, `nil` keeps the size. Images are never upscaled.
    var maxPixelSize: Int?
}

/// Image processing on top of ImageIO. All functions are synchronous and meant to run off the main thread.
enum ImageEngine {
    /// Re-encodes `source` as `format`, optionally downscaling.
    static func write(_ source: URL, as format: ImageFormat, to destination: URL, options: ImageWriteOptions) throws {
        let image = try SourceImage(url: source)
        let pixels = try image.orientedPixels(maxPixelSize: options.maxPixelSize)
        let properties = options.keepsMetadata ? image.metadataWithoutOrientation : [:]
        try encode(pixels, properties: properties, as: format, to: destination, quality: options.quality)
    }

    /// Removes metadata without re-encoding pixels when the format allows it. Orientation is always kept.
    static func removeMetadata(_ source: URL, to destination: URL, mode: MetadataRemoval, format: ImageFormat) throws {
        let image = try SourceImage(url: source)
        var options: [CFString: Any] = [:]
        switch mode {
        case .all:
            let metadata = CGImageMetadataCreateMutable()
            CGImageMetadataSetValueMatchingImageProperty(
                metadata, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation,
                NSNumber(value: image.orientation.rawValue)
            )
            options[kCGImageDestinationMetadata] = metadata
            options[kCGImageDestinationMergeMetadata] = false
        case .location:
            options[kCGImageDestinationMergeMetadata] = true
            options[kCGImageMetadataShouldExcludeGPS] = true
        }

        if try copyLosslessly(image, to: destination, format: format, options: options) {
            return
        }

        // Fallback: re-encode at high quality with the filtered properties.
        var properties = mode == .all ? [:] : image.metadataWithoutOrientation
        properties.removeValue(forKey: kCGImagePropertyGPSDictionary)
        try encode(image.orientedPixels(), properties: properties, as: format, to: destination, quality: 0.95)
    }

    /// Rotates 90° clockwise. JPEG, HEIC and TIFF only change their orientation tag, so no quality is lost.
    static func rotateClockwise(_ source: URL, to destination: URL, format: ImageFormat) throws {
        let image = try SourceImage(url: source)
        let options: [CFString: Any] = [
            kCGImageDestinationOrientation: NSNumber(value: image.orientation.rotatedClockwise.rawValue),
        ]
        if format.supportsLosslessOrientation, try copyLosslessly(
            image,
            to: destination,
            format: format,
            options: options
        ) {
            return
        }
        let rotated = try rotate(image.orientedPixels())
        try encode(rotated, properties: image.metadataWithoutOrientation, as: format, to: destination, quality: 0.95)
    }

    /// Decoded pixels as displayed (orientation applied), optionally downscaled.
    static func loadImage(_ url: URL, maxPixelSize: Int? = nil) throws -> CGImage {
        try SourceImage(url: url).orientedPixels(maxPixelSize: maxPixelSize)
    }

    /// Pixel size of the image as displayed (orientation applied).
    static func pixelSize(of url: URL) throws -> CGSize {
        try SourceImage(url: url).orientedSize
    }

    // MARK: - Encoding

    static func encode(
        _ image: CGImage,
        properties: [CFString: Any],
        as format: ImageFormat,
        to destination: URL,
        quality: Double
    ) throws {
        let image = format.supportsAlpha ? image : try flattened(image)
        switch format {
        case .webp:
            try WebPEncoder.encode(image, quality: quality).write(to: destination, options: .atomic)
        case .icns:
            try writeICNS(image, to: destination)
        default:
            guard let target = CGImageDestinationCreateWithURL(
                destination as CFURL, format.utType.identifier as CFString, 1, nil
            ) else {
                throw ImageEngineError.cannotWrite(format)
            }
            var properties = properties
            if format.isLossy {
                properties[kCGImageDestinationLossyCompressionQuality] = quality
            }
            CGImageDestinationAddImage(target, image, properties as CFDictionary)
            guard CGImageDestinationFinalize(target) else { throw ImageEngineError.cannotWrite(format) }
        }
    }

    private static func copyLosslessly(
        _ image: SourceImage,
        to destination: URL,
        format: ImageFormat,
        options: [CFString: Any]
    ) throws -> Bool {
        guard ImageFormat(type: image.type) == format,
              let target = CGImageDestinationCreateWithURL(
                  destination as CFURL, format.utType.identifier as CFString, 1, nil
              )
        else { return false }
        return CGImageDestinationCopyImageSource(target, image.source, options as CFDictionary, nil)
    }

    /// ICNS needs square images in fixed sizes; the image is centered on a transparent square.
    private static func writeICNS(_ image: CGImage, to destination: URL) throws {
        let sizes = [16, 32, 64, 128, 256, 512, 1024]
        guard let target = CGImageDestinationCreateWithURL(
            destination as CFURL, UTType.icns.identifier as CFString, sizes.count, nil
        ) else {
            throw ImageEngineError.cannotWrite(.icns)
        }
        for size in sizes {
            try CGImageDestinationAddImage(target, fitted(image, inSquare: size), nil)
        }
        guard CGImageDestinationFinalize(target) else { throw ImageEngineError.cannotWrite(.icns) }
    }

    // MARK: - Pixel operations

    private static func context(width: Int, height: Int, opaque: Bool = false) throws -> CGContext {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ImageEngineError.cannotWrite(.png)
        }
        context.interpolationQuality = .high
        return context
    }

    /// Composites transparent images onto white for formats without alpha.
    private static func flattened(_ image: CGImage) throws -> CGImage {
        guard image.hasAlpha else { return image }
        let context = try context(width: image.width, height: image.height, opaque: true)
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return try context.makeImage().orThrow(ImageEngineError.cannotWrite(.jpeg))
    }

    private static func rotate(_ image: CGImage) throws -> CGImage {
        let context = try context(width: image.height, height: image.width)
        // Rotate the coordinate system 90° clockwise (y axis points up in Core Graphics).
        context.translateBy(x: 0, y: CGFloat(image.width))
        context.rotate(by: -.pi / 2)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return try context.makeImage().orThrow(ImageEngineError.cannotWrite(.png))
    }

    private static func fitted(_ image: CGImage, inSquare side: Int) throws -> CGImage {
        let context = try context(width: side, height: side)
        let scale = CGFloat(side) / CGFloat(max(image.width, image.height))
        let width = CGFloat(image.width) * scale
        let height = CGFloat(image.height) * scale
        context.draw(
            image,
            in: CGRect(x: (CGFloat(side) - width) / 2, y: (CGFloat(side) - height) / 2, width: width, height: height)
        )
        return try context.makeImage().orThrow(ImageEngineError.cannotWrite(.icns))
    }
}

// MARK: - Source image

/// A decoded image file: its pixels, orientation and metadata.
private struct SourceImage {
    let source: CGImageSource
    let type: UTType
    let properties: [CFString: Any]

    init(url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let typeIdentifier = CGImageSourceGetType(source) as String?,
              let type = UTType(typeIdentifier)
        else {
            throw ImageEngineError.unreadable(url)
        }
        self.source = source
        self.type = type
        let index = CGImageSourceGetPrimaryImageIndex(source)
        properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
    }

    var orientation: CGImagePropertyOrientation {
        (properties[kCGImagePropertyOrientation] as? UInt32).flatMap(CGImagePropertyOrientation.init) ?? .up
    }

    var pixelSize: CGSize {
        CGSize(
            width: properties[kCGImagePropertyPixelWidth] as? Int ?? 0,
            height: properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        )
    }

    var orientedSize: CGSize {
        orientation.swapsDimensions ? CGSize(width: pixelSize.height, height: pixelSize.width) : pixelSize
    }

    /// Metadata dictionaries to carry over; orientation is reset because pixels are written upright.
    var metadataWithoutOrientation: [CFString: Any] {
        var metadata: [CFString: Any] = [:]
        for key in [
            kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary,
            kCGImagePropertyTIFFDictionary,
        ] {
            metadata[key] = properties[key]
        }
        if var tiff = metadata[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            metadata[kCGImagePropertyTIFFDictionary] = tiff
        }
        metadata[kCGImagePropertyOrientation] = 1
        return metadata
    }

    /// Full-resolution (or downscaled) pixels with orientation applied.
    func orientedPixels(maxPixelSize: Int? = nil) throws -> CGImage {
        let fullSize = Int(max(pixelSize.width, pixelSize.height))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixelSize ?? fullSize, fullSize),
        ]
        let index = CGImageSourceGetPrimaryImageIndex(source)
        return try CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
            .orThrow(ImageEngineError.cannotWrite(.png))
    }
}

extension CGImagePropertyOrientation {
    /// The orientation after rotating the displayed image a further 90° clockwise.
    var rotatedClockwise: CGImagePropertyOrientation {
        switch self {
        case .up: .right
        case .right: .down
        case .down: .left
        case .left: .up
        case .upMirrored: .rightMirrored
        case .rightMirrored: .downMirrored
        case .downMirrored: .leftMirrored
        case .leftMirrored: .upMirrored
        }
    }

    var swapsDimensions: Bool {
        [.left, .right, .leftMirrored, .rightMirrored].contains(self)
    }
}

extension CGImage {
    var hasAlpha: Bool {
        ![.none, .noneSkipFirst, .noneSkipLast].contains(alphaInfo)
    }
}

extension Optional {
    func orThrow(_ error: @autoclosure () -> some Error) throws -> Wrapped {
        guard let self else { throw error() }
        return self
    }
}
