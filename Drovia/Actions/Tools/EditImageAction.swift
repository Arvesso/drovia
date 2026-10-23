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
        let edited = await ImageEditor.edit(files, mode: mode, redaction: context.settings.redactionStyle)
        guard !edited.isEmpty else { throw CancellationError() }
        let quality = max(context.settings.imageQuality, 0.9)
        var result = ActionResult()
        for item in edited {
            do {
                var format = ImageFormat.output(for: UTType(filenameExtension: item.source.pathExtension) ?? .png)
                // Rounded corners or a transparent frame need a format with alpha.
                if !format.supportsAlpha, item.image.hasAlpha {
                    format = .png
                }
                let destination = await context.planner.destination(
                    for: item.source, action: "edited", fileExtension: format.fileExtension
                )
                try ImageEngine.encode(item.image, properties: [:], as: format, to: destination, quality: quality)
                result.processed.append(ProcessedFile(source: item.source, output: destination))
            } catch {
                result.failures.append(ActionFailure(file: item.source, message: error.localizedDescription))
            }
        }
        return result
    }
}
