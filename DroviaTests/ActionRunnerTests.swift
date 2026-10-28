@testable import Drovia
import Foundation
import Testing

/// The path where data can be lost: results recorded, originals trashed, and undo putting it all back.
@MainActor
struct ActionRunnerTests {
    private let folder: TemporaryFolder
    private let trash: TestTrash
    private let testDefaults = TestDefaults()
    private let settings: SettingsStore
    private let history: HistoryStore
    private let runner: ActionRunner

    init() throws {
        folder = try TemporaryFolder()
        trash = try TestTrash(in: folder.url)
        settings = SettingsStore(defaults: testDefaults.defaults)
        history = HistoryStore(fileURL: folder.url.appendingPathComponent("history.json"), trash: trash.move)
        runner = ActionRunner(
            settings: settings, toast: ToastPresenter(), history: history, shelf: ShelfController(), trash: trash.move
        )
    }

    private func png(_ name: String) throws -> URL {
        let url = folder.url.appendingPathComponent(name)
        try ImageEngine.encode(TestImages.solid(RGBA(0x3366AA)), properties: [:], as: .png, to: url, quality: 1)
        return url
    }

    @Test func recordsResultsAndUndoRemovesThem() async throws {
        let source = try png("photo.png")
        let (result, entry) = try await runner.execute(
            ImageConvertAction(format: .jpeg),
            on: [source],
            allowsPrompts: false
        )
        let output = try #require(result.outputs.first)
        #expect(FileManager.default.fileExists(atPath: output.path))
        #expect(FileManager.default.fileExists(atPath: source.path))

        try history.undo(#require(entry).id)
        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func trashedOriginalsComeBackOnUndo() async throws {
        settings.trashesOriginals = true
        let sources = try [png("a.png"), png("b.png")]
        let (result, entry) = try await runner.execute(
            ImageConvertAction(format: .jpeg),
            on: sources,
            allowsPrompts: false
        )
        #expect(result.outputs.count == 2)
        #expect(sources.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })

        try history.undo(#require(entry).id)
        #expect(sources.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(result.outputs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func zipTrashesEveryOriginal() async throws {
        settings.trashesOriginals = true
        let sources = try [png("a.png"), png("b.png"), png("c.png")]
        let (result, entry) = try await runner.execute(ZipAction(), on: sources, allowsPrompts: false)
        #expect(result.outputs.count == 1)
        #expect(sources.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        try history.undo(#require(entry).id)
        #expect(sources.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }
}
