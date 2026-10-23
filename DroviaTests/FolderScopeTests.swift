@testable import Drovia
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
