import Foundation
import UniformTypeIdentifiers

private func allPDFs(_ types: [UTType]) -> Bool {
    !types.isEmpty && types.allSatisfy { $0.conforms(to: .pdf) }
}

// MARK: - Convert

/// PDF pages to images, or the whole document to text.
struct PDFConvertAction: DroviaAction {
    enum Target: String, CaseIterable {
        case png, jpeg, tiff, text

        var title: String {
            self == .text ? "TXT" : rawValue.uppercased()
        }

        var imageFormat: ImageFormat? {
            switch self {
            case .png: .png
            case .jpeg: .jpeg
            case .tiff: .tiff
            case .text: nil
            }
        }
    }

    let target: Target

    var id: String {
        "convert.pdf.\(target.rawValue)"
    }

    var sectorID: String {
        target == .text ? "convert.txt" : "convert.\(target.rawValue)"
    }

    var wheel: WheelKind {
        .convert
    }

    var title: String {
        target.title
    }

    var progressTitle: String {
        String(localized: "Converting to \(target.title)")
    }

    var producesFiles: Bool {
        true
    }

    func supports(_ types: [UTType]) -> Bool {
        allPDFs(types)
    }

    func perform(_ files: [URL], context: ActionContext) async throws -> ActionResult {
        let planner = context.planner
        let target = target
        let quality = context.settings.imageQuality
        return await context.processEach(files) { source in
            guard let format = target.imageFormat else {
                let destination = await planner.destination(for: source, action: nil, fileExtension: "txt")
                try PDFEngine.text(of: source).write(to: destination, atomically: true, encoding: .utf8)
                return destination
            }
            let pages = try PDFEngine.pageCount(of: source)
            // One page becomes one image; several pages go into a folder named after the PDF.
            if pages == 1 {
                let destination = await planner.destination(
                    for: source,
                    action: nil,
                    fileExtension: format.fileExtension
                )
                try ImageEngine.encode(
                    PDFEngine.renderPage(0, of: source),
                    properties: [:],
                    as: format,
                    to: destination,
                    quality: quality
                )
                return destination
            }
            let folder = await planner.destination(for: source, action: nil, fileExtension: "")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            let name = source.deletingPathExtension().lastPathComponent
            for index in 0 ..< pages {
                let file = folder.appendingPathComponent(PDFEngine.pageFileName(
                    name,
                    index,
                    of: pages,
                    ext: format.fileExtension
                ))
                try ImageEngine.encode(
                    PDFEngine.renderPage(index, of: source),
                    properties: [:],
                    as: format,
                    to: file,
                    quality: quality
                )
            }
            return folder
        }
    }
}

// MARK: - Tools

struct PDFMergeAction: DroviaAction {
    let id = "tools.merge"
    let wheel = WheelKind.tools
    let symbol: String? = "rectangle.stack.badge.plus"
    let producesFiles = true

    var title: String {
        String(localized: "Merge")
    }

    var progressTitle: String {
        String(localized: "Merging")
    }

    /// Two or more PDFs and images, combined in the order they were dragged.
    func supports(_ types: [UTType]) -> Bool {
        types.count > 1 && types.allSatisfy { $0.conforms(to: .pdf) || ImageFormat.isReadableImage($0) }
    }

    func perform(_ files: [URL], context: ActionContext) async throws -> ActionResult {
        let destination = await context.planner.destination(for: files[0], action: "merged", fileExtension: "pdf")
        try await Task.detached { try PDFEngine.merge(files, to: destination) }.value
        return ActionResult(
            processed: [ProcessedFile(source: files[0], output: destination)],
            message: destination.lastPathComponent,
            detail: String(localized: "\(files.count) files merged")
        )
    }
}

struct PDFSplitAction: DroviaAction {
    let id = "tools.split"
    let wheel = WheelKind.tools
    let symbol: String? = "rectangle.split.3x1"
    let producesFiles = true

    var title: String {
        String(localized: "Split")
    }

    var progressTitle: String {
        String(localized: "Splitting")
    }

    func supports(_ types: [UTType]) -> Bool {
        allPDFs(types)
    }

    func perform(_ files: [URL], context: ActionContext) async throws -> ActionResult {
        let planner = context.planner
        return await context.processEach(files) { source in
            let folder = await planner.destination(for: source, action: "pages", fileExtension: "")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            _ = try PDFEngine.split(source, into: folder)
            return folder
        }
    }
}

/// A PDF tool that writes one new PDF per input.
struct PDFTransformAction: DroviaAction {
    enum Kind: String {
        case compress, rotate, metadata
    }

    let kind: Kind
    let wheel = WheelKind.tools
    let producesFiles = true

    var id: String {
        "tools.\(kind.rawValue).pdf"
    }

    var sectorID: String {
        "tools.\(kind.rawValue)"
    }

    var title: String {
        switch kind {
        case .compress: String(localized: "Compress")
        case .rotate: String(localized: "Rotate")
        case .metadata: String(localized: "Metadata")
        }
    }

    var symbol: String? {
        switch kind {
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .rotate: "rotate.right"
        case .metadata: "tag.slash"
        }
    }

    var progressTitle: String {
        switch kind {
        case .compress: String(localized: "Compressing")
        case .rotate: String(localized: "Rotating")
        case .metadata: String(localized: "Removing metadata")
        }
    }

    func supports(_ types: [UTType]) -> Bool {
        allPDFs(types)
    }

    func perform(_ files: [URL], context: ActionContext) async throws -> ActionResult {
        let planner = context.planner
        let kind = kind
        let suffix = switch kind {
        case .compress: "compressed"
        case .rotate: "rotated"
        case .metadata: "clean"
        }
        var result = await context.processEach(files) { source in
            let destination = await planner.destination(for: source, action: suffix, fileExtension: "pdf")
            switch kind {
            case .compress:
                try PDFEngine.compress(source, to: destination)
                guard let before = source.fileSize, let after = destination.fileSize, after < before * 97 / 100 else {
                    try? FileManager.default.removeItem(at: destination)
                    return nil
                }
            case .rotate:
                try PDFEngine.rotateClockwise(source, to: destination)
            case .metadata:
                try PDFEngine.removeMetadata(source, to: destination)
            }
            return destination
        }
        if kind == .compress, result.outputs.isEmpty, result.failures.isEmpty {
            result.message = String(localized: "Already as small as it gets")
        }
        return result
    }
}
