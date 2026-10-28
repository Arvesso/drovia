import CoreGraphics
import Foundation
import libwebp

/// Encodes WebP with libwebp; ImageIO can only read it.
enum WebPEncoder {
    static let maxSide = 16383

    /// `lossless` keeps every pixel exactly; `quality` (0...1) is then ignored. `exif` is an EXIF block
    /// (TIFF structure) to embed. Wide-gamut images keep their color space, with its ICC profile embedded;
    /// others are written as sRGB, which WebP assumes.
    static func encode(_ image: CGImage, quality: Double, lossless: Bool = false, exif: Data? = nil) throws -> Data {
        let width = image.width
        let height = image.height
        guard width <= maxSide, height <= maxSide else {
            throw ImageEngineError.tooLarge(.webp, maxSide: maxSide)
        }

        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? sRGB
        let profile = space.name == CGColorSpace.sRGB ? nil : space.copyICCData() as Data?

        let stride = width * 4
        var rgba = [UInt8](repeating: 0, count: stride * height)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: stride,
                space: profile == nil ? sRGB : space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw ImageEngineError.cannotWrite(.webp) }
        if image.hasAlpha {
            unpremultiply(&rgba)
        }

        var output: UnsafeMutablePointer<UInt8>?
        let size = rgba.withUnsafeBufferPointer {
            lossless
                ? WebPEncodeLosslessRGBA($0.baseAddress, Int32(width), Int32(height), Int32(stride), &output)
                : WebPEncodeRGBA(
                    $0.baseAddress,
                    Int32(width),
                    Int32(height),
                    Int32(stride),
                    Float(quality * 100),
                    &output
                )
        }
        guard size > 0, let output else { throw ImageEngineError.cannotWrite(.webp) }
        defer { WebPFree(output) }
        let bitstream = Data(bytes: output, count: size)
        guard exif != nil || profile != nil else { return bitstream }
        return try addChunks(to: bitstream, exif: exif, profile: profile)
    }

    /// Wraps a plain WebP in the extended format with EXIF and ICC chunks (libwebp's mux sets the flags).
    private static func addChunks(to bitstream: Data, exif: Data?, profile: Data?) throws -> Data {
        guard let mux = WebPMuxNew() else { throw ImageEngineError.cannotWrite(.webp) }
        defer { WebPMuxDelete(mux) }
        // Each call copies what it's given (copy_data = 1), so the buffers only need to live through it.
        func set(_ data: Data, _ add: (UnsafePointer<WebPData>) -> WebPMuxError) -> Bool {
            data.withUnsafeBytes { bytes in
                var chunk = WebPData(bytes: bytes.bindMemory(to: UInt8.self).baseAddress, size: bytes.count)
                return add(&chunk) == WEBP_MUX_OK
            }
        }
        guard set(bitstream, { WebPMuxSetImage(mux, $0, 1) }),
              exif.map({ set($0) { WebPMuxSetChunk(mux, "EXIF", $0, 1) } }) ?? true,
              profile.map({ set($0) { WebPMuxSetChunk(mux, "ICCP", $0, 1) } }) ?? true
        else { throw ImageEngineError.cannotWrite(.webp) }
        var assembled = WebPData()
        guard WebPMuxAssemble(mux, &assembled) == WEBP_MUX_OK, let bytes = assembled.bytes else {
            throw ImageEngineError.cannotWrite(.webp)
        }
        defer { WebPDataClear(&assembled) }
        return Data(bytes: bytes, count: assembled.size)
    }

    /// libwebp expects straight (non-premultiplied) alpha.
    private static func unpremultiply(_ rgba: inout [UInt8]) {
        for pixel in stride(from: 0, to: rgba.count, by: 4) {
            let alpha = Int(rgba[pixel + 3])
            guard alpha > 0, alpha < 255 else { continue }
            for channel in 0 ..< 3 {
                rgba[pixel + channel] = UInt8(min(255, (Int(rgba[pixel + channel]) * 255 + alpha / 2) / alpha))
            }
        }
    }
}
