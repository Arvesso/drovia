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

    /// Whether Drovia can work anywhere yet: some folders are allowed, or it has Full Disk Access.
    var hasAccess: Bool {
        hasFullDiskAccess || !folders.isEmpty
    }

    func allows(_ content: DragContent) -> Bool {
        // Full Disk Access may have been granted since we last looked; checking is one cheap file test.
        if !hasFullDiskAccess {
            refreshFullDiskAccess()
        }
        // Promised files and raw images are written into our own temporary folder.
        return content.fileURLs.allSatisfy(allows)
    }

    func allows(_ url: URL) -> Bool {
        hasFullDiskAccess || folders.contains { FolderScope.contains($0.path, path: url.path) }
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
            // Already covered by an allowed folder around it; and folders inside the new one become redundant.
            guard !folders.contains(where: { FolderScope.contains($0.path, path: path) }) else { continue }
            folders.removeAll { FolderScope.contains(path, path: $0.path) }
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
              let stored = try? JSONDecoder().decode([Lossy<AllowedFolder>].self, from: data).compactMap(\.value)
        else { return }
        folders = stored.map(resolvingBookmark)
        // Only when a folder moved or its bookmark was renewed. (Unit tests run inside the app, so an
        // unconditional save rewrote the developer's real settings on every test run.)
        if folders != stored {
            save()
        }
    }

    private func resolvingBookmark(_ folder: AllowedFolder) -> AllowedFolder {
        guard let bookmark = folder.bookmark else { return folder }
        var isStale = false
        // At launch: never show UI or mount a network share or disk that isn't there; the stored path is used.
        let options: URL.BookmarkResolutionOptions = [.withoutUI, .withoutMounting]
        guard let url = try? URL(
            resolvingBookmarkData: bookmark, options: options, relativeTo: nil, bookmarkDataIsStale: &isStale
        ) else { return folder }
        // A folder moved to the Trash isn't one the user means to allow any more.
        guard !url.path.contains("/.Trash/") else { return folder }
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
