import AppKit
import Observation
import os

struct AllowedFolder: Identifiable, Codable, Equatable {
    var id = UUID()
    var path: String
    /// Keeps track of the folder if it is renamed or moved.
    var bookmark: Data?

    var url: URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }

    var isHome: Bool {
        path == NSHomeDirectory()
    }

    var displayName: String {
        isHome ? String(localized: "Home") : url.lastPathComponent
    }

    var abbreviatedPath: String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}

/// Folders Drovia is allowed to work in, plus Full Disk Access status.
@MainActor
@Observable
final class FolderAccess {
    private static let defaultsKey = "allowedFolders"

    private(set) var folders: [AllowedFolder] = []
    private(set) var hasFullDiskAccess = false

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
        refreshFullDiskAccess()
    }

    // MARK: - Queries

    func allows(_ content: DragContent) -> Bool {
        // Promised files and raw images are written into our own temporary folder.
        content.fileURLs.allSatisfy(allows)
    }

    func allows(_ url: URL) -> Bool {
        folders.contains { FolderScope.contains($0.path, path: url.path) }
    }

    /// Full Disk Access can't be queried directly; reading a file only it unlocks never shows a prompt.
    func refreshFullDiskAccess() {
        hasFullDiskAccess = FileManager.default.isReadableFile(
            atPath: "/Library/Application Support/com.apple.TCC/TCC.db"
        )
    }

    // MARK: - Editing

    func add(_ urls: [URL]) {
        for url in urls {
            let path = url.standardizedFileURL.path
            guard !folders.contains(where: { $0.path == path }) else { continue }
            let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            folders.append(AllowedFolder(path: path, bookmark: bookmark))
            requestAccess(to: path)
        }
        folders.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        save()
    }

    func addHomeFolder() {
        add([URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)])
    }

    func remove(_ folder: AllowedFolder) {
        folders.removeAll { $0.id == folder.id }
        save()
    }

    func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        panel.prompt = String(localized: "Allow")
        panel.message = String(localized: "Drovia will work with files in these folders and all their subfolders.")
        NSApp.activate()
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            MainActor.assumeIsolated { self?.add(panel.urls) }
        }
    }

    // MARK: - Private

    /// Lists the folder and the protected folders around it once, so macOS asks for access now.
    private func requestAccess(to path: String) {
        let paths = [path] + FolderScope.protectedFolders(relatedTo: path)
        Task.detached(priority: .userInitiated) {
            for path in paths {
                _ = try? FileManager.default.contentsOfDirectory(atPath: path)
            }
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let stored = try? JSONDecoder().decode([AllowedFolder].self, from: data)
        else { return }
        folders = stored.map(resolvingBookmark)
        save()
    }

    private func resolvingBookmark(_ folder: AllowedFolder) -> AllowedFolder {
        guard let bookmark = folder.bookmark else { return folder }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale) else { return folder }
        var resolved = folder
        resolved.path = url.standardizedFileURL.path
        if isStale {
            resolved.bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        return resolved
    }

    private func save() {
        do {
            try defaults.set(JSONEncoder().encode(folders), forKey: Self.defaultsKey)
        } catch {
            Logger.wheel.error("Failed to save allowed folders: \(error.localizedDescription)")
        }
    }
}
