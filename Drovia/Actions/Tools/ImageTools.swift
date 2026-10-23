import Foundation
import UniformTypeIdentifiers

/// Formats the image tools can process in place.
private func isEditableImage(_ type: UTType) -> Bool {
    ImageFormat.isReadableImage(type) && ImageFormat(type: type) != .gif
}

private func outputFormat(for file: URL) -> ImageFormat {
    ImageFormat.output(for: UTType(filenameExtension: file.pathExtension) ?? .png)
}

// MARK: - Compress

struct CompressAction: DroviaAction {
    let id = "tools.compress"
    let wheel = WheelKind.tools
    let symbol: String? = "arrow.down.right.and.arrow.up.left"
    let producesFiles = true

    var title: String {
        String(localized: "Compress")
    }

    var progressTitle: String {
        String(localized: "Compressing")
    }

    func supports(_ types: [UTType]) -> Bool {
        !types.isEmpty && types.allSatisfy(isEditableImage)
    }

    func perform(_ files: [URL], context: ActionContext) async throws -> ActionResult {
        let planner = context.planner
        let settings = context.settings
        let options = ImageWriteOptions(
            quality: min(settings.imageQuality, 0.75),
            keepsMetadata: !settings.compressRemovesMetadata,
            maxPixelSize: settings.compressMaxDimension > 0 ? settings.compressMaxDimension : nil
        )
        var result = await context.processEach(files) { source in
            let format = outputFormat(for: source)
            let destination = await planner.destination(
                for: source, action: "compressed", fileExtension: format.fileExtension
            )
            try ImageEngine.write(source, as: format, to: destination, options: options)
            // Keep the result only if it actually saves space.
            guard let before = source.fileSize, let after = destination.fileSize, after < before * 97 / 100 else {
                try? FileManager.default.removeItem(at: destination)
                return nil
            }
            return destination
        }
        if result.outputs.isEmpty, result.failures.isEmpty {
            result.message = String(localized: "Already as small as it gets")
        }
        return result
    }
}

// MARK: - Metadata

struct RemoveMetadataAction: DroviaAction {
    let id = "tools.metadata"
    let wheel = WheelKind.tools
    let symbol: String? = "tag.slash"
    let producesFiles = true

    var title: String {
        String(localized: "Metadata")
    }

    var progressTitle: String {
        String(localized: "Removing metadata")
    }

    func supports(_ types: [UTType]) -> Bool {
        !types.isEmpty && types.allSatisfy(isEditableImage)
    }

    func perform(_ files: [URL], context: ActionContext) async throws -> ActionResult {
        let planner = context.planner
        let mode = context.settings.metadataRemoval
        return await context.processEach(files) { source in
            let format = outputFormat(for: source)
            let destination = await planner.destination(
                for: source,
                action: "clean",
                fileExtension: format.fileExtension
            )
            try ImageEngine.removeMetadata(source, to: destination, mode: mode, format: format)
            return destination
        }
    }
}

// MARK: - Resize

enum ResizePreset: String, CaseIterable, Identifiable, Sendable {
    case half, side1024, side1600, side2048, side3840

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .half: "50%"
        case .side1024: "1024 px"
        case .side1600: "1600 px"
        case .side2048: "2048 px"
        case .side3840: "3840 px (4K)"
        }
    }

    /// Longest side for an image whose longest side is `side`.
    func targetSide(for side: Int) -> Int {
        switch self {
        case .half: max(1, side / 2)
        case .side1024: min(side, 1024)
        case .side1600: min(side, 1600)
        case .side2048: min(side, 2048)
        case .side3840: min(side, 3840)
        }
    }
}

struct ResizeAction: DroviaAction {
    let id = "tools.resize"
    let wheel = WheelKind.tools
    let symbol: String? = "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left"
    let producesFiles = true

    var title: String {
        String(localized: "Resize")
    }

    var progressTitle: String {
        String(localized: "Resizing")
    }

    func supports(_ types: [UTType]) -> Bool {
        !types.isEmpty && types.allSatisfy(isEditableImage)
    }

    func perform(_ files: [URL], context: ActionContext) async throws -> ActionResult {
        let planner = context.planner
        let preset = context.settings.resizePreset
        let quality = context.settings.imageQuality
        return await context.processEach(files) { source in
            let size = try ImageEngine.pixelSize(of: source)
            let side = Int(max(size.width, size.height))
            let target = preset.targetSide(for: side)
            // Never upscale; an image already within the preset is left alone.
            guard target < side else { return nil }
            let format = outputFormat(for: source)
            let destination = await planner.destination(
                for: source,
                action: "resized",
                fileExtension: format.fileExtension
            )
            let options = ImageWriteOptions(quality: max(quality, 0.85), keepsMetadata: true, maxPixelSize: target)
            try ImageEngine.write(source, as: format, to: destination, options: options)
            return destination
        }
    }
}

// MARK: - Rotate

struct RotateAction: DroviaAction {
    let id = "tools.rotate"
    let wheel = WheelKind.tools
    let symbol: String? = "rotate.right"
    let producesFiles = true

    var title: String {
        String(localized: "Rotate")
    }

    var progressTitle: String {
        String(localized: "Rotating")
    }

    func supports(_ types: [UTType]) -> Bool {
        !types.isEmpty && types.allSatisfy(isEditableImage)
    }

    func perform(_ files: [URL], context: ActionContext) async throws -> ActionResult {
        let planner = context.planner
        return await context.processEach(files) { source in
            let format = outputFormat(for: source)
            let destination = await planner.destination(
                for: source,
                action: "rotated",
                fileExtension: format.fileExtension
            )
            try ImageEngine.rotateClockwise(source, to: destination, format: format)
            return destination
        }
    }
}

extension URL {
    var fileSize: Int? {
        (try? resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }
}
