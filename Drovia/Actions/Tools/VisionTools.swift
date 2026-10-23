import AppKit
import UniformTypeIdentifiers

private func allImages(_ types: [UTType]) -> Bool {
    !types.isEmpty && types.allSatisfy { ImageFormat.isReadableImage($0) && ImageFormat(type: $0) != .gif }
}

struct RemoveBackgroundAction: DroviaAction {
    let id = "tools.removebg"
    let wheel = WheelKind.tools
    let symbol: String? = "person.crop.rectangle.badge.plus"
    let producesFiles = true

    var title: String {
        String(localized: "Remove BG")
    }

    var progressTitle: String {
        String(localized: "Removing background")
    }

    func supports(_ types: [UTType]) -> Bool {
        allImages(types)
    }

    func perform(_ files: [URL], context: ActionContext) async throws -> ActionResult {
        let planner = context.planner
        let crops = context.settings.removeBackgroundCrops
        // The model is heavy; one image at a time.
        return await context.processEach(files, concurrency: 1) { source, _ in
            let cutout = try VisionEngine.removeBackground(from: ImageEngine.loadImage(source), cropToSubject: crops)
            // Transparency needs PNG whatever the source format.
            let destination = await planner.destination(for: source, action: "nobg", fileExtension: "png")
            try ImageEngine.encode(cutout, properties: [:], as: .png, to: destination, quality: 1)
            return destination
        }
    }
}

struct RedactAction: DroviaAction {
    let id = "tools.redact"
    let wheel = WheelKind.tools
    let symbol: String? = "eye.slash"
    let producesFiles = true

    var title: String {
        String(localized: "Redact")
    }

    var progressTitle: String {
        String(localized: "Redacting")
    }

    func supports(_ types: [UTType]) -> Bool {
        allImages(types)
    }

    func perform(_ files: [URL], context: ActionContext) async throws -> ActionResult {
        let planner = context.planner
        let style = context.settings.redactionStyle
        let targets = context.settings.redactionTargets
        let quality = max(context.settings.imageQuality, 0.9)
        var result = await context.processEach(files, concurrency: 2) { source, _ in
            let image = try ImageEngine.loadImage(source)
            let regions = try VisionEngine.sensitiveRegions(in: image, targets: targets)
            guard !regions.isEmpty else { return nil }
            let redacted = try VisionEngine.redact(image, regions: regions, style: style)
            let format = ImageFormat.output(for: UTType(filenameExtension: source.pathExtension) ?? .png)
            let destination = await planner.destination(
                for: source,
                action: "redacted",
                fileExtension: format.fileExtension
            )
            // Metadata is dropped on purpose: it can hold the very things being hidden (location, names).
            try ImageEngine.encode(redacted, properties: [:], as: format, to: destination, quality: quality)
            return destination
        }
        if result.outputs.isEmpty, result.failures.isEmpty {
            result.message = String(localized: "Nothing to redact found")
            result.detail = String(localized: "Use Annotate to hide areas by hand")
        }
        return result
    }
}

/// Recognizes text in images (and PDFs without a text layer) and copies it.
struct RecognizeTextAction: DroviaAction {
    let id = "tools.text"
    let wheel = WheelKind.tools
    let symbol: String? = "text.viewfinder"

    var title: String {
        String(localized: "Text")
    }

    var progressTitle: String {
        String(localized: "Recognizing text")
    }

    func supports(_ types: [UTType]) -> Bool {
        !types.isEmpty && types.allSatisfy { $0.conforms(to: .pdf) || allImages([$0]) }
    }

    func perform(_ files: [URL], context: ActionContext) async throws -> ActionResult {
        var texts: [String] = []
        for (index, file) in files.enumerated() {
            let text = try await Task.detached { try Self.text(of: file) }.value
            if !text.isEmpty {
                texts.append(text)
            }
            context.reportProgress(Double(index + 1) / Double(files.count))
        }
        guard !texts.isEmpty else {
            return ActionResult(message: String(localized: "No text found"))
        }
        let text = texts.joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return ActionResult(message: String(localized: "Text copied"), detail: firstLine)
    }

    private nonisolated static func text(of file: URL) throws -> String {
        guard UTType(filenameExtension: file.pathExtension)?.conforms(to: .pdf) == true else {
            return try VisionEngine.text(in: ImageEngine.loadImage(file))
        }
        // Use the PDF's own text when it has one; scans get OCR page by page.
        let embedded = try PDFEngine.text(of: file).trimmingCharacters(in: .whitespacesAndNewlines)
        if !embedded.isEmpty {
            return embedded
        }
        return try (0 ..< PDFEngine.pageCount(of: file))
            .map { try VisionEngine.text(in: PDFEngine.renderPage($0, of: file)) }
            .joined(separator: "\n\n")
    }
}
