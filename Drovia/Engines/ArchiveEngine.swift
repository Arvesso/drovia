import CryptoKit
import Foundation
import UniformTypeIdentifiers

enum ArchiveEngine {
    struct ToolError: LocalizedError {
        let errorDescription: String?
    }

    /// Archive types `tar` (libarchive) can extract. Not `public.archive` as a whole: disk images, Apple
    /// Archives and installer packages conform to it, and those people want to zip or share, not extract.
    static let extractableTypes: [UTType] = [
        .zip, .gzip, .bz2,
        UTType("org.tukaani.xz-archive"), UTType("org.tukaani.tar-xz-archive"), UTType("public.tar-archive"),
        UTType("org.7-zip.7-zip-archive"), UTType("com.rarlab.rar-archive"), UTType("public.cpio-archive"),
    ].compactMap(\.self)

    static func isExtractable(_ type: UTType) -> Bool {
        extractableTypes.contains { type.conforms(to: $0) }
    }

    /// Zips files with Finder-compatible metadata. Several items from different folders are
    /// staged as clones in a temporary folder so they sit at the archive root.
    static func zip(_ items: [URL], to destination: URL) async throws {
        if items.count == 1 {
            try await removingOnFailure(destination) {
                try await run(
                    "/usr/bin/ditto",
                    ["-c", "-k", "--sequesterRsrc", "--keepParent", items[0].path, destination.path]
                )
            }
            return
        }
        // Staged on the items' own volume, where copies are clones, rather than copied to the startup disk.
        let fileManager = FileManager.default
        let parent = (try? fileManager.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: items[0], create: true
        )) ?? fileManager.temporaryDirectory
        let staging = parent.appendingPathComponent("Zip-\(UUID().uuidString)")
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: parent == fileManager.temporaryDirectory ? staging : parent) }
        for item in items {
            let name = NamingTemplate.uniqueFileName(
                base: item.deletingPathExtension().lastPathComponent, fileExtension: item.pathExtension
            ) { fileManager.fileExists(atPath: staging.appendingPathComponent($0).path) }
            try fileManager.copyItem(at: item, to: staging.appendingPathComponent(name))
        }
        try await removingOnFailure(destination) {
            try await run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", staging.path, destination.path])
        }
    }

    /// Extracts into `folder`. Like Archive Utility, an archive holding a single item extracts to just
    /// that item next to the archive instead of a folder inside a folder. Returns what was created.
    static func extract(_ archive: URL, into folder: URL) async throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Not into an existing folder: its files could be overwritten.
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: false)
        // No half-extracted folder is left behind (a damaged or password-protected archive).
        try await removingOnFailure(folder) {
            try await extractContents(of: archive, into: folder)
        }

        let contents = try fileManager.contentsOfDirectory(atPath: folder.path)
            .filter { $0 != "__MACOSX" && $0 != ".DS_Store" }
        guard contents.count == 1 else { return folder }
        let item = folder.appendingPathComponent(contents[0])
        let parent = folder.deletingLastPathComponent()
        // Move out via a temporary name: the item may be called exactly like its container folder.
        let temporary = parent.appendingPathComponent(".drovia-\(UUID().uuidString)")
        try fileManager.moveItem(at: item, to: temporary)
        try fileManager.removeItem(at: folder)
        do {
            return try moveToFreeName(temporary, in: parent, base: item)
        } catch {
            // Never strand the extracted item under a hidden name.
            try? fileManager.createDirectory(at: folder, withIntermediateDirectories: false)
            try? fileManager.moveItem(at: temporary, to: item)
            throw error
        }
    }

    private static func extractContents(of archive: URL, into folder: URL) async throws {
        let fileExtension = archive.pathExtension.lowercased()
        let isTar = archive.deletingPathExtension().pathExtension.lowercased() == "tar"
        switch fileExtension {
        case "zip":
            try await run("/usr/bin/ditto", ["-x", "-k", archive.path, folder.path])
        // A single compressed file, not a tar archive inside one: tar would misread it.
        case "gz" where !isTar, "gzip" where !isTar:
            try await decompress(archive, with: "/usr/bin/gzip", into: folder)
        case "bz2" where !isTar:
            try await decompress(archive, with: "/usr/bin/bzip2", into: folder)
        case "xz" where !isTar:
            throw ToolError(errorDescription: String(localized: "Single .xz files can't be extracted"))
        default:
            try await run("/usr/bin/tar", ["-xf", archive.path, "-C", folder.path])
        }
    }

    /// Writes the decompressed stream of `file` ("notes.txt.gz") to "notes.txt" in `folder`.
    private static func decompress(_ file: URL, with tool: String, into folder: URL) async throws {
        let destination = folder.appendingPathComponent(file.deletingPathExtension().lastPathComponent)
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: destination.path])
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = ["-dc", file.path]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let status = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<
            Int32,
            any Error
        >) in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        guard status == 0 else {
            throw ToolError(errorDescription: String(localized: "Can't extract \(file.lastPathComponent)"))
        }
    }

    /// Moves `item` into `folder` under `base`'s name, or the next free one. Retries if another job takes
    /// the name between checking and moving.
    private static func moveToFreeName(_ item: URL, in folder: URL, base: URL) throws -> URL {
        let fileManager = FileManager.default
        while true {
            let name = NamingTemplate.uniqueFileName(
                base: base.deletingPathExtension().lastPathComponent, fileExtension: base.pathExtension
            ) { fileManager.fileExists(atPath: folder.appendingPathComponent($0).path) }
            let destination = folder.appendingPathComponent(name)
            do {
                try fileManager.moveItem(at: item, to: destination)
                return destination
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            }
        }
    }

    /// Hex SHA-256, read in chunks so large files don't fill memory.
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func run(_ tool: String, _ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: ToolError(errorDescription: message?.isEmpty == false
                            ? message : "\(tool) failed (\(process.terminationStatus))"))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
