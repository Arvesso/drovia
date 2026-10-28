import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageEngineError: LocalizedError {
    case unreadable(URL)
    case cannotWrite(ImageFormat)
    case tooLarge(ImageFormat, maxSide: Int)
    case severalFrames(URL)

    var errorDescription: String? {
        switch self {
        case let .unreadable(url):
            String(localized: "Can't read \(url.lastPathComponent) as an image")
        case let .cannotWrite(format):
            String(localized: "Can't write \(format.title)")
        case let .tooLarge(format, maxSide):
            String(localized: "\(format.title) images can't be larger than \(maxSide) px")
        case let .severalFrames(url):
            String(localized: "\(url.lastPathComponent) is animated or has several pages; only PDF keeps them all")
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
        let properties = options.keepsMetadata ? image.metadataWithoutOrientation : [:]
        if image.hasSeveralFrames {
            // Other formats would silently keep only the first frame or page.
            guard format == .pdf else { throw ImageEngineError.severalFrames(source) }
            try writePages(of: image, to: destination, maxPixelSize: options.maxPixelSize)
            return
        }
        let pixels = try image.orientedPixels(maxPixelSize: options.maxPixelSize)
        try encode(pixels, properties: properties, as: format, to: destination, quality: options.quality)
    }

    /// Every frame of an animated image or page of a multi-page TIFF, as the pages of a PDF.
    private static func writePages(of image: SourceImage, to destination: URL, maxPixelSize: Int?) throws {
        let count = CGImageSourceGetCount(image.source)
        guard let target = CGImageDestinationCreateWithURL(
            destination as CFURL, UTType.pdf.identifier as CFString, count, nil
        ) else {
            throw ImageEngineError.cannotWrite(.pdf)
        }
        for index in 0 ..< count {
            try CGImageDestinationAddImage(target, image.orientedPixels(at: index, maxPixelSize: maxPixelSize), nil)
        }
        guard CGImageDestinationFinalize(target) else { throw ImageEngineError.cannotWrite(.pdf) }
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
            // GPS, plus the place names IPTC and XMP keep (city, country…), which also say where it was taken.
            let metadata = CGImageMetadataCreateMutable()
            for key in locationIPTCKeys {
                CGImageMetadataSetValueMatchingImageProperty(metadata, kCGImagePropertyIPTCDictionary, key, kCFNull)
            }
            options[kCGImageDestinationMetadata] = metadata
            options[kCGImageDestinationMergeMetadata] = true
            options[kCGImageMetadataShouldExcludeGPS] = true
        }

        if try copyLosslessly(image, to: destination, format: format, options: options) {
            return
        }

        // Fallback: re-encode with the filtered properties.
        guard !image.hasSeveralFrames else { throw ImageEngineError.severalFrames(source) }
        var properties = mode == .all ? [:] : image.metadataWithoutOrientation
        properties.removeValue(forKey: kCGImagePropertyGPSDictionary)
        if var iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any] {
            locationIPTCKeys.forEach { iptc.removeValue(forKey: $0) }
            properties[kCGImagePropertyIPTCDictionary] = iptc
        }
        try encode(
            image.orientedPixels(),
            properties: properties,
            as: format,
            to: destination,
            quality: format.reencodeQuality
        )
    }

    private static var locationIPTCKeys: [CFString] {
        [
            kCGImagePropertyIPTCCity, kCGImagePropertyIPTCSubLocation, kCGImagePropertyIPTCProvinceState,
            kCGImagePropertyIPTCCountryPrimaryLocationName, kCGImagePropertyIPTCCountryPrimaryLocationCode,
        ]
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
        guard !image.hasSeveralFrames else { throw ImageEngineError.severalFrames(source) }
        let rotated = try rotate(image.orientedPixels())
        try encode(
            rotated,
            properties: image.metadataWithoutOrientation,
            as: format,
            to: destination,
            quality: format.reencodeQuality
        )
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
            try WebPEncoder.encode(image, quality: quality, lossless: quality >= 1, exif: exifBlock(from: properties))
                .write(to: destination, options: .atomic)
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
            if format == .tiff {
                // ImageIO writes TIFF uncompressed by default, often larger than the source.
                var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
                tiff[kCGImagePropertyTIFFCompression] = 5 // LZW
                properties[kCGImagePropertyTIFFDictionary] = tiff
            }
            CGImageDestinationAddImage(target, image, properties as CFDictionary)
            guard CGImageDestinationFinalize(target) else { throw ImageEngineError.cannotWrite(format) }
        }
    }

    /// The EXIF block (camera, date, location…) ImageIO would write for `properties`, for WebP, which ImageIO
    /// can't write. Taken from a 1×1 JPEG written with those properties, so the format is exactly ImageIO's.
    static func exifBlock(from properties: [CFString: Any]) -> Data? {
        let keys = [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyTIFFDictionary]
        guard keys.contains(where: { properties[$0] != nil }),
              let pixel = CGContext(
                  data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )?.makeImage()
        else { return nil }
        let jpeg = NSMutableData()
        guard let target = CGImageDestinationCreateWithData(jpeg, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(target, pixel, properties as CFDictionary)
        guard CGImageDestinationFinalize(target) else { return nil }

        // JPEG segments: FF xx, then a big-endian length that counts itself. EXIF is APP1 (FFE1) "Exif\0\0".
        let bytes = [UInt8](jpeg as Data)
        var index = 2
        while index + 4 <= bytes.count, bytes[index] == 0xFF, bytes[index + 1] != 0xDA {
            let length = Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            let payload = index + 4 ..< min(index + 2 + length, bytes.count)
            if bytes[index + 1] == 0xE1, bytes[payload].starts(with: Array("Exif\0\0".utf8)) {
                return Data(bytes[payload].dropFirst(6))
            }
            index += 2 + length
        }
        return nil
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

    /// A context for redrawing `image`: wide-gamut (Display P3) and 16-bit images keep their color space and
    /// depth, which an 8-bit sRGB context would clip and band.
    private static func context(
        width: Int,
        height: Int,
        opaque: Bool = false,
        like image: CGImage
    ) throws -> CGContext {
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: image.bitsPerComponent > 8 ? 16 : 8,
            bytesPerRow: 0, space: space,
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
        let context = try context(width: image.width, height: image.height, opaque: true, like: image)
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return try context.makeImage().orThrow(ImageEngineError.cannotWrite(.jpeg))
    }

    private static func rotate(_ image: CGImage) throws -> CGImage {
        let context = try context(width: image.height, height: image.width, like: image)
        // Rotate the coordinate system 90° clockwise (y axis points up in Core Graphics).
        context.translateBy(x: 0, y: CGFloat(image.width))
        context.rotate(by: -.pi / 2)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return try context.makeImage().orThrow(ImageEngineError.cannotWrite(.png))
    }

    private static func fitted(_ image: CGImage, inSquare side: Int) throws -> CGImage {
        let context = try context(width: side, height: side, like: image)
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

    /// Animated GIF/PNG/WebP/HEICS, or a multi-page TIFF. Other formats' extra images (JPEG's multi-picture
    /// previews) aren't frames of the picture.
    var hasSeveralFrames: Bool {
        CGImageSourceGetCount(source) > 1
            && [UTType.gif, .png, .webP, .tiff, UTType("public.heics")].contains { $0.map(type.conforms) == true }
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
        // EXIF's pixel size would be wrong after resizing or turning; ImageIO writes the real one.
        if var exif = metadata[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif.removeValue(forKey: kCGImagePropertyExifPixelXDimension)
            exif.removeValue(forKey: kCGImagePropertyExifPixelYDimension)
            metadata[kCGImagePropertyExifDictionary] = exif
        }
        // Resolution, so a 144 dpi Retina screenshot doesn't come out twice as large in print and layouts.
        metadata[kCGImagePropertyDPIWidth] = properties[kCGImagePropertyDPIWidth]
        metadata[kCGImagePropertyDPIHeight] = properties[kCGImagePropertyDPIHeight]
        metadata[kCGImagePropertyOrientation] = 1
        return metadata
    }

    /// Full-resolution (or downscaled) pixels with orientation applied.
    func orientedPixels(at frame: Int? = nil, maxPixelSize: Int? = nil) throws -> CGImage {
        let index = frame ?? CGImageSourceGetPrimaryImageIndex(source)
        let frameProperties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? properties
        let fullSize = max(
            frameProperties[kCGImagePropertyPixelWidth] as? Int ?? 0,
            frameProperties[kCGImagePropertyPixelHeight] as? Int ?? 0
        )
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixelSize ?? fullSize, fullSize),
        ]
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
