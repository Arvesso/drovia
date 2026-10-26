import AppKit
import PDFKit
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
        let untouched = result.processed.count(where: { $0.output == nil })
        if result.outputs.isEmpty, result.failures.isEmpty {
            result.message = String(localized: "Nothing to redact found")
            result.detail = String(localized: "Use Annotate to hide areas by hand")
        } else if untouched > 0 {
            // Otherwise those files look processed and might be shared as they are.
            result.detail = String(localized: "\(untouched) files had nothing to redact")
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
        var failures: [ActionFailure] = []
        for (index, file) in files.enumerated() {
            try Task.checkCancellation()
            do {
                let text = try await Task.detached { try Self.text(of: file) }.value
                if !text.isEmpty {
                    texts.append(text)
                }
            } catch {
                // One unreadable file shouldn't lose the text of the others.
                failures.append(ActionFailure(file: file, message: error.localizedDescription))
            }
            context.reportProgress(Double(index + 1) / Double(files.count))
        }
        guard !texts.isEmpty else {
            return failures.isEmpty ? ActionResult(message: String(localized: "No text found"))
                : ActionResult(failures: failures)
        }
        let text = texts.joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        // Some text was copied, so this is a success that mentions the files left out.
        let detail = failures.isEmpty ? firstLine : String(localized: "\(failures.count) files couldn't be read")
        return ActionResult(message: String(localized: "Text copied"), detail: detail)
    }

    private nonisolated static func text(of file: URL) throws -> String {
        guard UTType(filenameExtension: file.pathExtension)?.conforms(to: .pdf) == true else {
            return try VisionEngine.text(in: ImageEngine.loadImage(file))
        }
        // Pages with a text layer use it; scanned pages get OCR. Decided per page, since scans often come
        // with a typed cover page or a stamped header.
        let document = try PDFEngine.open(file)
        var pages: [String] = []
        for index in 0 ..< document.pageCount {
            guard let page = document.page(at: index) else { continue }
            var text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.isEmpty, let image = PDFEngine.render(page, scale: ocrScale(for: page)) {
                text = try VisionEngine.text(in: image)
            }
            if !text.isEmpty {
                pages.append(text)
            }
        }
        return pages.joined(separator: "\n\n")
    }

    /// About 300 dpi, the resolution scans are made at, so small print survives; capped for huge pages.
    private nonisolated static func ocrScale(for page: PDFPage) -> CGFloat {
        let bounds = page.bounds(for: .cropBox)
        return min(300.0 / 72, 8000 / max(bounds.width, bounds.height, 1))
    }
}
