import AppKit
import UniformTypeIdentifiers

/// Something Drovia can do with dropped files; each action is one sector on a wheel.
@MainActor
protocol DroviaAction {
    var id: String { get }
    var wheel: WheelKind { get }
    var title: String { get }
    /// SF Symbol; actions without one (file formats) show their title large.
    var symbol: String? { get }
    /// Shown while the action runs, e.g. "Converting".
    var progressTitle: String { get }
    /// Whether the action writes new files (and so needs an output location).
    var producesFiles: Bool { get }

    func supports(_ types: [UTType]) -> Bool
    func perform(_ files: [URL], context: ActionContext) async throws -> ActionResult
}

extension DroviaAction {
    var symbol: String? {
        nil
    }

    var progressTitle: String {
        title
    }

    var producesFiles: Bool {
        false
    }

    var wheelItem: WheelItem {
        WheelItem(id: id, title: title, symbol: symbol)
    }
}

struct ProcessedFile: Sendable {
    var source: URL
    /// `nil` when the file was left as is (e.g. already as small as it gets).
    var output: URL?
}

struct ActionFailure: Sendable {
    var file: URL
    var message: String
}

struct ActionResult {
    var processed: [ProcessedFile] = []
    var failures: [ActionFailure] = []
    /// Overrides the default summary, e.g. "Copied 3 paths".
    var message: String?
    var detail: String?
    /// Off for actions with their own visible effect (a share sheet, a new window).
    var showsConfirmation = true

    static let silent = ActionResult(showsConfirmation: false)

    var outputs: [URL] {
        processed.compactMap(\.output)
    }
}

/// Everything an action needs while running.
@MainActor
struct ActionContext {
    let settings: SettingsStore
    let planner: OutputPlanner
    let reportProgress: (Double) -> Void

    /// Runs `work` for every file in parallel, reporting progress and collecting failures.
    func processEach(
        _ files: [URL],
        _ work: @escaping @Sendable (URL) async throws -> URL?
    ) async -> ActionResult {
        var result = ActionResult()
        let limit = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)
        await withTaskGroup(of: (URL, Result<URL?, any Error>).self) { group in
            var pending = files.makeIterator()
            func addNext() {
                guard let file = pending.next() else { return }
                group.addTask {
                    do { return try await (file, .success(work(file))) } catch { return (file, .failure(error)) }
                }
            }
            for _ in 0 ..< limit {
                addNext()
            }
            var finished = 0
            for await (file, outcome) in group {
                switch outcome {
                case let .success(output):
                    result.processed.append(ProcessedFile(source: file, output: output))
                case let .failure(error):
                    result.failures.append(ActionFailure(file: file, message: error.localizedDescription))
                }
                finished += 1
                reportProgress(Double(finished) / Double(files.count))
                addNext()
            }
        }
        return result
    }
}

extension DragContent {
    /// Types of the dragged items, derived from names only so no file is touched.
    var contentTypes: [UTType] {
        if !fileURLs.isEmpty {
            return fileURLs.map { url in
                url.hasDirectoryPath ? .folder : UTType(filenameExtension: url.pathExtension) ?? .data
            }
        }
        if !promisedTypes.isEmpty {
            return promisedTypes
        }
        return Array(repeating: hasImageData ? .png : .data, count: itemCount)
    }
}
