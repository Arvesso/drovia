import Foundation
import UniformTypeIdentifiers

/// Crop, Annotate and Add BG: open the image editor in the matching mode.
struct EditImageAction: DroviaAction {
    let mode: EditorMode
    let wheel = WheelKind.tools
    let producesFiles = true
    let isInteractive = true

    var id: String {
        switch mode {
        case .crop: "tools.crop"
        case .annotate: "tools.annotate"
        case .background: "tools.addbg"
        }
    }

    var title: String {
        switch mode {
        case .crop: String(localized: "Crop")
        case .annotate: String(localized: "Annotate")
        case .background: String(localized: "Add BG")
        }
    }

    var symbol: String? {
        switch mode {
        case .crop: "crop"
        case .annotate: "pencil.tip.crop.circle"
        case .background: "photo.on.rectangle"
        }
    }

    func supports(_ types: [UTType]) -> Bool {
        !types.isEmpty && types.allSatisfy { ImageFormat.isReadableImage($0) && ImageFormat(type: $0) != .gif }
    }

    func perform(_ files: [URL], context: ActionContext) async throws -> ActionResult {
        let quality = max(context.settings.imageQuality, 0.9)
        let planner = context.planner
        var result = ActionResult()
        // Each image is written as soon as it's saved in the editor, off the main thread.
        await ImageEditor.edit(files, mode: mode, redaction: context.settings.redactionStyle) { item in
            do {
                var format = ImageFormat.output(for: UTType(filenameExtension: item.source.pathExtension) ?? .png)
                // Rounded corners or a transparent frame need a format with alpha.
                if !format.supportsAlpha, item.image.hasAlpha {
                    format = .png
                }
                let destination = await planner.destination(
                    for: item.source, action: "edited", fileExtension: format.fileExtension
                )
                let image = item.image
                try await Task.detached(priority: .userInitiated) {
                    try ImageEngine.encode(image, properties: [:], as: format, to: destination, quality: quality)
                }.value
                result.processed.append(ProcessedFile(source: item.source, output: destination))
            } catch {
                result.failures.append(ActionFailure(file: item.source, message: error.localizedDescription))
            }
        }
        guard !result.processed.isEmpty || !result.failures.isEmpty else { throw CancellationError() }
        return result
    }
}
