import CoreImage
import Foundation
import Vision

enum VisionEngineError: LocalizedError {
    case noSubject

    var errorDescription: String? {
        String(localized: "Couldn't find a subject to cut out")
    }
}

enum RedactionStyle: String, CaseIterable, Identifiable, Sendable {
    case pixelate, blur, blackBox

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .pixelate: String(localized: "Pixelate")
        case .blur: String(localized: "Blur")
        case .blackBox: String(localized: "Black box")
        }
    }
}

/// What automatic redaction looks for.
struct RedactionTargets: OptionSet, Sendable {
    let rawValue: Int

    static let faces = RedactionTargets(rawValue: 1 << 0)
    /// Email addresses, phone numbers, card numbers and links in recognized text.
    static let personalText = RedactionTargets(rawValue: 1 << 1)
    static let codes = RedactionTargets(rawValue: 1 << 2)
    static let all: RedactionTargets = [.faces, .personalText, .codes]
}

/// Vision-based image analysis. Rectangles are in image pixels with the origin at the top left.
enum VisionEngine {
    // MARK: - Background removal

    /// The image with everything but the foreground subject(s) made transparent.
    static func removeBackground(from image: CGImage, cropToSubject: Bool) throws -> CGImage {
        let handler = VNImageRequestHandler(cgImage: image)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw VisionEngineError.noSubject
        }
        let buffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: cropToSubject
        )
        let ciImage = CIImage(cvPixelBuffer: buffer)
        return try CIContext().createCGImage(
            ciImage,
            from: ciImage.extent,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        .orThrow(VisionEngineError.noSubject)
    }

    // MARK: - Text

    static func recognizeText(in image: CGImage) throws -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        return request.results ?? []
    }

    /// Recognized text, one line per observation, in the order Vision returns them.
    static func text(in image: CGImage) throws -> String {
        try recognizeText(in: image)
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    // MARK: - Redaction

    static func sensitiveRegions(in image: CGImage, targets: RedactionTargets) throws -> [CGRect] {
        let size = CGSize(width: image.width, height: image.height)
        let handler = VNImageRequestHandler(cgImage: image)
        var regions: [CGRect] = []

        if targets.contains(.faces) {
            let request = VNDetectFaceRectanglesRequest()
            try handler.perform([request])
            // Faces get some margin so hair and chin are covered too.
            regions += (request.results ?? []).map { pixelRect($0.boundingBox, in: size).insetBy(
                dx: -0.15,
                dy: -0.15,
                relative: true
            ) }
        }
        if targets.contains(.codes) {
            let request = VNDetectBarcodesRequest()
            try handler.perform([request])
            regions += (request.results ?? []).map { pixelRect($0.boundingBox, in: size).insetBy(
                dx: -0.05,
                dy: -0.05,
                relative: true
            ) }
        }
        if targets.contains(.personalText) {
            regions += try sensitiveTextRegions(in: image, size: size)
        }
        let bounds = CGRect(origin: .zero, size: size)
        return regions.map { $0.intersection(bounds) }.filter { !$0.isEmpty }
    }

    /// Searches all recognized lines joined together, so a card number or phone number wrapped onto the
    /// next line (or split into separate observations) is still found. Each part of a match is covered on
    /// its own line; when Vision can't locate a part precisely, its whole line is covered.
    private static func sensitiveTextRegions(in image: CGImage, size: CGSize) throws -> [CGRect] {
        let lines = try recognizeText(in: image).compactMap { observation in
            observation.topCandidates(1).first.map { (observation: observation, candidate: $0) }
        }
        var text = ""
        var starts: [Int] = []
        for line in lines {
            starts.append((text as NSString).length)
            text += line.candidate.string + " "
        }
        var regions: [CGRect] = []
        for match in sensitiveRanges(in: text).map({ NSRange($0, in: text) }) {
            for (index, line) in lines.enumerated() {
                let string = line.candidate.string
                let lineRange = NSRange(location: starts[index], length: (string as NSString).length)
                guard let overlap = match.intersection(lineRange), overlap.length > 0 else { continue }
                let local = NSRange(location: overlap.location - lineRange.location, length: overlap.length)
                let box = Range(local, in: string).flatMap { try? line.candidate.boundingBox(for: $0)?.boundingBox }
                let rect = pixelRect(box ?? line.observation.boundingBox, in: size)
                // Vision's text boxes clip ascenders, descenders and edge glyphs; pad by the line height.
                let padding = max(2, rect.height * 0.3)
                regions.append(rect.insetBy(dx: -padding, dy: -padding))
            }
        }
        return regions
    }

    /// Ranges of emails, phone numbers, links and card-like digit runs.
    static func sensitiveRanges(in string: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        let types: NSTextCheckingResult.CheckingType = [.phoneNumber, .link]
        if let detector = try? NSDataDetector(types: types.rawValue) {
            let matches = detector.matches(in: string, range: NSRange(string.startIndex..., in: string))
            ranges += matches.compactMap { Range($0.range, in: string) }
        }
        // 13–19 digits, optionally grouped by spaces or dashes: payment cards and similar numbers.
        if let cards = try? NSRegularExpression(pattern: #"\b(?:\d[ -]?){12,18}\d\b"#) {
            let matches = cards.matches(in: string, range: NSRange(string.startIndex..., in: string))
            ranges += matches.compactMap { Range($0.range, in: string) }
        }
        return ranges
    }

    /// Covers `regions` of `image` in the given style. `pixelScale` is the image's pixels per pixel of the
    /// original, for a downscaled preview: the minimum blur and block sizes then shrink with it, so the
    /// preview looks as strong as the saved file rather than stronger.
    static func redact(
        _ image: CGImage, regions: [CGRect], style: RedactionStyle, pixelScale: CGFloat = 1
    ) throws -> CGImage {
        let height = CGFloat(image.height)
        var output = CIImage(cgImage: image)
        let original = output
        for region in regions {
            // Core Image puts the origin at the bottom left.
            let rect = CGRect(x: region.minX, y: height - region.maxY, width: region.width, height: region.height)
            let cover: CIImage
            switch style {
            case .blackBox:
                cover = CIImage(color: .black).cropped(to: rect)
            case .pixelate:
                let scale = max(8 * pixelScale, max(rect.width, rect.height) / 10)
                // Blurring first makes the blocks impossible to match against rendered text (as Depix does).
                cover = original.clampedToExtent()
                    .applyingGaussianBlur(sigma: scale / 2)
                    .applyingFilter(
                        "CIPixellate",
                        parameters: [kCIInputScaleKey: scale, kCIInputCenterKey: CIVector(cgPoint: rect.origin)]
                    )
                    .cropped(to: rect)
            case .blur:
                let radius = max(12 * pixelScale, min(rect.width, rect.height) / 4)
                cover = original.clampedToExtent()
                    .applyingGaussianBlur(sigma: radius)
                    .cropped(to: rect)
            }
            output = cover.composited(over: output)
        }
        return try CIContext().createCGImage(output, from: original.extent)
            .orThrow(ImageEngineError.cannotWrite(.png))
    }

    /// Vision's normalized, bottom-left-origin rectangle in top-left-origin pixels.
    static func pixelRect(_ normalized: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: normalized.minX * size.width,
            y: (1 - normalized.maxY) * size.height,
            width: normalized.width * size.width,
            height: normalized.height * size.height
        )
    }
}

private extension CGRect {
    func insetBy(dx: CGFloat, dy: CGFloat, relative: Bool) -> CGRect {
        relative ? insetBy(dx: width * dx, dy: height * dy) : insetBy(dx: dx, dy: dy)
    }
}
