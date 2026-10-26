@testable import Drovia
import Foundation
import Testing

@MainActor
struct HistoryStoreTests {
    private let folder: TemporaryFolder
    private let store: HistoryStore

    init() throws {
        folder = try TemporaryFolder()
        store = HistoryStore(fileURL: folder.url.appendingPathComponent("history.json"))
    }

    private func makeFile(_ name: String) throws -> URL {
        let url = folder.url.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        return url
    }

    @Test func undoMovesFilesBack() throws {
        let original = folder.url.appendingPathComponent("a.txt")
        let moved = try makeFile("b.txt")
        let entry = store.add(
            title: "Move",
            symbol: "folder",
            outputs: [moved],
            undo: [.moveBack(from: moved, to: original)]
        )
        try store.undo(entry.id)
        #expect(FileManager.default.fileExists(atPath: original.path))
        #expect(!FileManager.default.fileExists(atPath: moved.path))
        #expect(store.entries.first?.isUndone == true)
        #expect(store.lastUndoable == nil)
    }

    @Test func undoSkipsStepsThatNoLongerApply() throws {
        let gone = folder.url.appendingPathComponent("gone.txt")
        let entry = store.add(title: "Convert", symbol: "x", outputs: [], undo: [.trashCreated(gone)])
        try store.undo(entry.id)
        #expect(store.entries.first?.isUndone == true)
    }

    @Test func undoPutsFileBackUnderFreeNameWhenOriginalNameIsTaken() throws {
        let original = try makeFile("a.txt")
        let moved = try makeFile("moved.txt")
        let entry = store.add(
            title: "Move",
            symbol: "folder",
            outputs: [moved],
            undo: [.moveBack(from: moved, to: original)]
        )
        try store.undo(entry.id)
        #expect(FileManager.default.fileExists(atPath: folder.url.appendingPathComponent("a 2.txt").path))
        #expect(FileManager.default.fileExists(atPath: original.path))
        #expect(store.entries.first?.isUndone == true)
    }

    @Test func undoReportsFilesThatAreGoneAndStaysUndoable() throws {
        let gone = folder.url.appendingPathComponent("gone.txt")
        let original = folder.url.appendingPathComponent("a.txt")
        let entry = store.add(
            title: "Move",
            symbol: "folder",
            outputs: [],
            undo: [.restore(trashed: gone, original: original)]
        )
        #expect(throws: UndoError.self) { try store.undo(entry.id) }
        #expect(store.lastUndoable?.id == entry.id)
    }

    @Test func undoingTwiceSaysNothingToUndo() throws {
        let entry = try store.add(
            title: "Convert",
            symbol: "x",
            outputs: [],
            undo: [.trashCreated(makeFile("out.txt"))]
        )
        try store.undo(entry.id)
        #expect(throws: UndoError.self) { try store.undo(entry.id) }
    }

    @Test func persistsEntries() {
        store.add(title: "Zip", symbol: "doc.zipper", outputs: [], undo: [])
        let reloaded = HistoryStore(fileURL: folder.url.appendingPathComponent("history.json"))
        #expect(reloaded.entries.map(\.title) == ["Zip"])
    }
}
