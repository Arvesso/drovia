import ImageIO
import UniformTypeIdentifiers

enum ImageFormat: String, CaseIterable, Sendable {
    case png, jpeg, webp, heic, avif, tiff, pdf, icns, bmp, gif

    /// Formats offered on the Convert wheel, in wheel order.
    static let convertTargets: [ImageFormat] = [.png, .jpeg, .webp, .heic, .avif, .tiff, .pdf, .icns]

    var utType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .webp: .webP
        case .heic: .heic
        case .avif: UTType("public.avif") ?? UTType(importedAs: "public.avif")
        case .tiff: .tiff
        case .pdf: .pdf
        case .icns: .icns
        case .bmp: .bmp
        case .gif: .gif
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        default: rawValue
        }
    }

    var title: String {
        rawValue.uppercased()
    }

    var isLossy: Bool {
        [.jpeg, .webp, .heic, .avif].contains(self)
    }

    var supportsAlpha: Bool {
        ![.jpeg, .bmp].contains(self)
    }

    /// Formats whose orientation tag can be changed without re-encoding pixels.
    var supportsLosslessOrientation: Bool {
        [.jpeg, .heic, .tiff].contains(self)
    }

    /// The format of a file of this type, if it is one we know.
    init?(type: UTType) {
        guard let format = Self.allCases.first(where: { type.conforms(to: $0.utType) }) else { return nil }
        self = format
    }

    /// Format to write when processing a file of `type` in place: the same format when we can write it,
    /// otherwise PNG (e.g. JPEG XL or RAW files, which ImageIO only reads).
    static func output(for type: UTType) -> ImageFormat {
        guard let format = ImageFormat(type: type), format != .pdf else { return .png }
        return format
    }

    /// Image types ImageIO can decode (PDF is not among them).
    static let readableTypes: [UTType] = (CGImageSourceCopyTypeIdentifiers() as? [String] ?? [])
        .compactMap(UTType.init)
        .filter { $0.conforms(to: .image) }

    static func isReadableImage(_ type: UTType) -> Bool {
        readableTypes.contains { type.conforms(to: $0) }
    }
}
