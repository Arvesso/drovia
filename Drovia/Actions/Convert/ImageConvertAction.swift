import Foundation
import UniformTypeIdentifiers

struct ImageConvertAction: DroviaAction {
    let format: ImageFormat

    var id: String {
        "convert.\(format.rawValue)"
    }

    var wheel: WheelKind {
        .convert
    }

    var title: String {
        format.title
    }

    var progressTitle: String {
        String(localized: "Converting to \(format.title)")
    }

    var producesFiles: Bool {
        true
    }

    func supports(_ types: [UTType]) -> Bool {
        // Offer only conversions that change something for at least one file.
        types.allSatisfy(ImageFormat.isReadableImage) && types.contains { ImageFormat(type: $0) != format }
    }

    func perform(_ files: [URL], context: ActionContext) async throws -> ActionResult {
        let format = format
        let planner = context.planner
        let options = ImageWriteOptions(
            quality: context.settings.imageQuality,
            keepsMetadata: context.settings.keepsMetadataOnConvert
        )
        return await context.processEach(files) { source in
            // In a mixed drop, files already in this format are left alone rather than copied.
            guard ImageFormat(type: FileType.of(source)) != format else { return nil }
            let destination = await planner.destination(for: source, action: nil, fileExtension: format.fileExtension)
            try ImageEngine.write(source, as: format, to: destination, options: options)
            return destination
        }
    }
}
