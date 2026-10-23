import AppKit
import UniformTypeIdentifiers

struct ZipAction: DroviaAction {
    let id = "actions.zip"
    let wheel = WheelKind.actions
    let symbol: String? = "doc.zipper"
    let producesFiles = true

    var title: String {
        String(localized: "Zip")
    }

    var progressTitle: String {
        String(localized: "Zipping")
    }

    /// Archives get Unzip instead.
    func supports(_ types: [UTType]) -> Bool {
        !types.isEmpty && !types.allSatisfy(ArchiveEngine.isExtractable)
    }

    func perform(_ files: [URL], context: ActionContext) async throws -> ActionResult {
        // Like Finder: one item becomes "<name>.zip" (photo.png.zip), several become "Archive.zip".
        let base = files.count == 1 ? files[0] : files[0].deletingLastPathComponent().appendingPathComponent("Archive")
        let destination = await context.planner.destination(
            for: base.appendingPathExtension("zip"), action: nil, fileExtension: "zip"
        )
        try await ArchiveEngine.zip(files, to: destination)
        return ActionResult(
            processed: [ProcessedFile(source: files[0], output: destination)],
            message: destination.lastPathComponent,
            detail: destination.fileSize.map { Int64($0).formatted(.byteCount(style: .file)) }
        )
    }
}

struct UnzipAction: DroviaAction {
    let id = "actions.unzip"
    let wheel = WheelKind.actions
    let symbol: String? = "arrow.up.bin"
    let producesFiles = true

    var title: String {
        String(localized: "Unzip")
    }

    var progressTitle: String {
        String(localized: "Extracting")
    }

    func supports(_ types: [UTType]) -> Bool {
        !types.isEmpty && types.allSatisfy(ArchiveEngine.isExtractable)
    }

    func perform(_ files: [URL], context: ActionContext) async throws -> ActionResult {
        let planner = context.planner
        return await context.processEach(files) { archive in
            // "photos.tar.gz" extracts into "photos". The planner drops one extension from the source name,
            // so pass the archive name minus its own extensions.
            var base = archive.deletingPathExtension()
            if base.pathExtension == "tar" {
                base = base.deletingPathExtension()
            }
            let folder = await planner.destination(
                for: base.appendingPathExtension("archive"),
                action: nil,
                fileExtension: ""
            )
            return try await ArchiveEngine.extract(archive, into: folder)
        }
    }
}

struct ChecksumAction: DroviaAction {
    let id = "tools.checksum"
    let wheel = WheelKind.tools
    let symbol: String? = "number"

    var title: String {
        String(localized: "Checksum")
    }

    var progressTitle: String {
        String(localized: "Calculating")
    }

    /// Images, PDFs and videos have their own tools; checksums are for everything else.
    func supports(_ types: [UTType]) -> Bool {
        !types.isEmpty && types.allSatisfy {
            !$0.conforms(to: .folder) && !$0.conforms(to: .pdf) && !ImageFormat.isReadableImage($0)
                && !MediaEngine.isVideo($0)
        }
    }

    func perform(_ files: [URL], context: ActionContext) async throws -> ActionResult {
        var lines: [String] = []
        for (index, file) in files.enumerated() {
            let hash = try await Task.detached { try ArchiveEngine.sha256(of: file) }.value
            lines.append(files.count == 1 ? hash : "\(hash)  \(file.lastPathComponent)")
            context.reportProgress(Double(index + 1) / Double(files.count))
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
        return ActionResult(
            message: String(localized: "SHA-256 copied"),
            detail: files.count == 1 ? lines[0] : String(localized: "\(files.count) files")
        )
    }
}
