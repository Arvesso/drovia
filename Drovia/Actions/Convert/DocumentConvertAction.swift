import AppKit
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

    /// One file at a time. HTML is read on the main thread (WebKit); everything else is converted in the
    /// background, so a long document doesn't freeze the app.
    func perform(_ files: [URL], context: ActionContext) async throws -> ActionResult {
        var result = ActionResult()
        let format = format
        let paperSize = NSPrintInfo.shared.paperSize
        for (index, source) in files.enumerated() {
            do {
                let destination = await context.planner.destination(
                    for: source, action: nil, fileExtension: format.fileExtension
                )
                if DocumentEngine.needsMainThread(source) {
                    try DocumentEngine.convert(source, to: format, at: destination, paperSize: paperSize)
                } else {
                    try await Task.detached(priority: .userInitiated) {
                        try DocumentEngine.convert(source, to: format, at: destination, paperSize: paperSize)
                    }.value
                }
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
