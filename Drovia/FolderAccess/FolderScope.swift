import Foundation

/// Pure path logic for allowed folders. Works on path strings only, so checking a dragged file
/// never touches the file system and never triggers a macOS privacy prompt.
enum FolderScope {
    /// Whether `path` is `folder` itself or anything inside it.
    static func contains(_ folder: String, path: String) -> Bool {
        let folder = normalized(folder)
        let path = normalized(path)
        return folder == "/" || path == folder || path.hasPrefix(folder + "/")
    }

    /// Privacy-protected folders that are `folder` itself, inside it, or contain it.
    /// Touching each of them once makes macOS ask for access right away instead of mid-drag.
    static func protectedFolders(relatedTo folder: String, home: String = NSHomeDirectory()) -> [String] {
        ["Desktop", "Documents", "Downloads"]
            .map { normalized(home) + "/" + $0 }
            .filter { contains(folder, path: $0) || contains($0, path: folder) }
    }

    private static func normalized(_ path: String) -> String {
        let standardized = (path as NSString).standardizingPath
        return standardized.count > 1 && standardized.hasSuffix("/") ? String(standardized.dropLast()) : standardized
    }
}
