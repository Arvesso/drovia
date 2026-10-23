import Foundation
import UniformTypeIdentifiers

struct DocumentConvertAction: DroviaAction {
    let format: DocumentFormat

    var id: String {
        "convert.doc.\(format.rawValue)"
    }

    var sectorID: String {
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
        !types.isEmpty && types.allSatisfy(DocumentFormat.isReadable)
            && types.contains { !$0.conforms(to: format.utType) }
    }

    /// Runs on the main actor one file at a time: AppKit text import and printing aren't thread-safe.
    func perform(_ files: [URL], context: ActionContext) async throws -> ActionResult {
        var result = ActionResult()
        for (index, source) in files.enumerated() {
            do {
                let destination = await context.planner.destination(
                    for: source, action: nil, fileExtension: format.fileExtension
                )
                try DocumentEngine.write(DocumentEngine.read(source), as: format, to: destination)
                result.processed.append(ProcessedFile(source: source, output: destination))
            } catch {
                result.failures.append(ActionFailure(file: source, message: error.localizedDescription))
            }
            context.reportProgress(Double(index + 1) / Double(files.count))
            await Task.yield()
        }
        return result
    }
}
