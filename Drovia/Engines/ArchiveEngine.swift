import CryptoKit
import Foundation
import UniformTypeIdentifiers

enum ArchiveEngine {
    struct ToolError: LocalizedError {
        let errorDescription: String?
    }

    /// Archive types `tar` (libarchive) can extract.
    static let extractableTypes: [UTType] = [
        .zip, .gzip, .bz2, .archive,
        UTType("org.tukaani.xz-archive"), UTType("public.tar-archive"), UTType("org.7-zip.7-zip-archive"),
        UTType("com.rarlab.rar-archive"),
    ].compactMap(\.self)

    static func isExtractable(_ type: UTType) -> Bool {
        extractableTypes.contains { type.conforms(to: $0) }
    }

    /// Zips files with Finder-compatible metadata. Several items from different folders are
    /// staged as clones in a temporary folder so they sit at the archive root.
    static func zip(_ items: [URL], to destination: URL) async throws {
        if items.count == 1 {
            try await run(
                "/usr/bin/ditto",
                ["-c", "-k", "--sequesterRsrc", "--keepParent", items[0].path, destination.path]
            )
            return
        }
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("Zip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        for item in items {
            let name = NamingTemplate.uniqueFileName(
                base: item.deletingPathExtension().lastPathComponent, fileExtension: item.pathExtension
            ) { FileManager.default.fileExists(atPath: staging.appendingPathComponent($0).path) }
            try FileManager.default.copyItem(at: item, to: staging.appendingPathComponent(name))
        }
        try await run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", staging.path, destination.path])
    }

    /// Extracts into `folder`. Like Archive Utility, an archive holding a single item extracts to just
    /// that item next to the archive instead of a folder inside a folder. Returns what was created.
    static func extract(_ archive: URL, into folder: URL) async throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        if archive.pathExtension.lowercased() == "zip" {
            try await run("/usr/bin/ditto", ["-x", "-k", archive.path, folder.path])
        } else {
            try await run("/usr/bin/tar", ["-xf", archive.path, "-C", folder.path])
        }

        let contents = try fileManager.contentsOfDirectory(atPath: folder.path)
            .filter { $0 != "__MACOSX" && $0 != ".DS_Store" }
        guard contents.count == 1 else { return folder }
        let item = folder.appendingPathComponent(contents[0])
        let parent = folder.deletingLastPathComponent()
        let name = NamingTemplate.uniqueFileName(
            base: item.deletingPathExtension().lastPathComponent, fileExtension: item.pathExtension
        ) { $0 != folder.lastPathComponent && fileManager.fileExists(atPath: parent.appendingPathComponent($0).path) }
        // Move out via a temporary name: the item may be called exactly like its container folder.
        let temporary = parent.appendingPathComponent(".drovia-\(UUID().uuidString)")
        try fileManager.moveItem(at: item, to: temporary)
        try fileManager.removeItem(at: folder)
        let destination = parent.appendingPathComponent(name)
        try fileManager.moveItem(at: temporary, to: destination)
        return destination
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
        let result = try await Subprocess.run(tool, arguments)
        guard result.status == 0 else {
            throw ToolError(errorDescription: result.errorMessage ?? "\(tool) failed (\(result.status))")
        }
    }
}
