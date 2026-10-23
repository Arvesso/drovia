import CoreGraphics
import Foundation
import libwebp

/// Encodes WebP with libwebp; ImageIO can only read it.
enum WebPEncoder {
    static let maxSide = 16383

    static func encode(_ image: CGImage, quality: Double) throws -> Data {
        let width = image.width
        let height = image.height
        guard width <= maxSide, height <= maxSide else {
            throw ImageEngineError.tooLarge(.webp, maxSide: maxSide)
        }

        let stride = width * 4
        var rgba = [UInt8](repeating: 0, count: stride * height)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: stride,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
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
            WebPEncodeRGBA($0.baseAddress, Int32(width), Int32(height), Int32(stride), Float(quality * 100), &output)
        }
        guard size > 0, let output else { throw ImageEngineError.cannotWrite(.webp) }
        defer { WebPFree(output) }
        return Data(bytes: output, count: size)
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
