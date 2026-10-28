@testable import Drovia
import Foundation
import Testing

struct FolderScopeTests {
    @Test func containsFolderItselfAndDescendants() {
        #expect(FolderScope.contains("/Users/me", path: "/Users/me"))
        #expect(FolderScope.contains("/Users/me", path: "/Users/me/Desktop/a.png"))
        #expect(FolderScope.contains("/Users/me/", path: "/Users/me/a.png"))
    }

    @Test func rejectsSiblingsWithSharedPrefix() {
        #expect(!FolderScope.contains("/Users/me", path: "/Users/meow/a.png"))
        #expect(!FolderScope.contains("/Users/me/Desktop", path: "/Users/me/a.png"))
    }

    @Test func rootContainsEverything() {
        #expect(FolderScope.contains("/", path: "/Volumes/Drive/file.txt"))
    }

    @Test func normalizesDotSegments() {
        #expect(FolderScope.contains("/Users/me", path: "/Users/me/Projects/../Desktop/a.png"))
        #expect(!FolderScope.contains("/Users/me/Projects", path: "/Users/me/Projects/../a.png"))
    }

    @Test func protectedFoldersInsideHome() {
        let found = FolderScope.protectedFolders(relatedTo: "/Users/me", home: "/Users/me")
        #expect(found == ["/Users/me/Desktop", "/Users/me/Documents", "/Users/me/Downloads"])
    }

    @Test func protectedFolderContainingSubfolder() {
        let found = FolderScope.protectedFolders(relatedTo: "/Users/me/Documents/Work", home: "/Users/me")
        #expect(found == ["/Users/me/Documents"])
    }

    @Test func unrelatedFolderHasNoProtectedFolders() {
        #expect(FolderScope.protectedFolders(relatedTo: "/Users/me/dev", home: "/Users/me").isEmpty)
    }
}

@MainActor
struct FolderAccessTests {
    private let folder: TemporaryFolder
    private let testDefaults = TestDefaults()

    init() throws {
        folder = try TemporaryFolder()
    }

    private func directory(_ path: String) throws -> URL {
        let url = folder.url.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func nestedFoldersAreNotListedTwice() throws {
        let access = FolderAccess(defaults: testDefaults.defaults)
        let inner = try directory("Work/Photos")
        let outer = try directory("Work")
        access.add([inner])
        access.add([outer])
        // The outer folder covers the inner one, which is dropped; adding inside it again changes nothing.
        #expect(access.folders.map(\.url.lastPathComponent) == ["Work"])
        try access.add([directory("Work/Other")])
        #expect(access.folders.count == 1)
    }
}

@MainActor
struct ShelfTests {
    @Test func followsRenamedFilesAndDropsDeletedOnes() throws {
        let folder = try TemporaryFolder()
        let kept = folder.url.appendingPathComponent("a.txt")
        let gone = folder.url.appendingPathComponent("b.txt")
        try Data("a".utf8).write(to: kept)
        try Data("b".utf8).write(to: gone)
        let shelf = ShelfController()
        shelf.model.items = [ShelfItem(url: kept), ShelfItem(url: gone)]

        let renamed = folder.url.appendingPathComponent("renamed.txt")
        try FileManager.default.moveItem(at: kept, to: renamed)
        try FileManager.default.removeItem(at: gone)
        shelf.pruneMissingFiles()
        #expect(shelf.model.items.map(\.url.lastPathComponent) == ["renamed.txt"])
    }
}
