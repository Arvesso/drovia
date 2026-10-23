import Foundation
import Observation
import os

/// One reversible file operation.
enum UndoStep: Codable, Equatable {
    /// A file Drovia created; undone by moving it to the Trash.
    case trashCreated(URL)
    /// A file Drovia moved; undone by moving it back.
    case moveBack(from: URL, to: URL)
    /// An original Drovia moved to the Trash; undone by putting it back.
    case restore(trashed: URL, original: URL)
}

struct HistoryEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var date = Date.now
    var title: String
    var symbol: String
    var outputs: [URL]
    var undo: [UndoStep]
    var isUndone = false

    var canUndo: Bool {
        !undo.isEmpty && !isUndone
    }
}

/// Recent file operations, persisted across launches, with undo.
@MainActor
@Observable
final class HistoryStore {
    private static let limit = 30

    private(set) var entries: [HistoryEntry] = []

    @ObservationIgnored private let fileURL: URL?

    init(fileURL: URL? = HistoryStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    var lastUndoable: HistoryEntry? {
        entries.first(where: \.canUndo)
    }

    @discardableResult
    func add(title: String, symbol: String, outputs: [URL], undo: [UndoStep]) -> HistoryEntry {
        let entry = HistoryEntry(title: title, symbol: symbol, outputs: outputs, undo: undo)
        entries.insert(entry, at: 0)
        entries = Array(entries.prefix(Self.limit))
        save()
        return entry
    }

    /// Reverts an entry, newest step first. Steps that already can't apply (file gone) are skipped.
    func undo(_ id: HistoryEntry.ID) throws {
        guard let index = entries.firstIndex(where: { $0.id == id }), entries[index].canUndo else { return }
        let fileManager = FileManager.default
        var firstError: (any Error)?
        for step in entries[index].undo.reversed() {
            do {
                switch step {
                case let .trashCreated(url):
                    guard fileManager.fileExists(atPath: url.path) else { continue }
                    try fileManager.trashItem(at: url, resultingItemURL: nil)
                case let .moveBack(from, to), let .restore(from, to):
                    guard fileManager.fileExists(atPath: from.path),
                          !fileManager.fileExists(atPath: to.path) else { continue }
                    try fileManager.moveItem(at: from, to: to)
                }
            } catch {
                Logger.wheel.error("Undo step failed: \(error.localizedDescription)")
                firstError = firstError ?? error
            }
        }
        entries[index].isUndone = true
        save()
        if let firstError {
            throw firstError
        }
    }

    func clear() {
        entries.removeAll()
        save()
    }

    // MARK: - Persistence

    nonisolated static var defaultFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Drovia", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        entries = (try? JSONDecoder().decode([HistoryEntry].self, from: data)) ?? []
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            Logger.wheel.error("Failed to save history: \(error.localizedDescription)")
        }
    }
}
