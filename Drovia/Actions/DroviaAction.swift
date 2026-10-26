import AppKit
import UniformTypeIdentifiers

/// Something Drovia can do with dropped files; each action is one sector on a wheel.
@MainActor
protocol DroviaAction {
    var id: String { get }
    /// The wheel sector this action appears as. Variants of one action for different file kinds
    /// (Compress for images, PDFs and videos) share a sector, so users order and hide them together.
    var sectorID: String { get }
    var wheel: WheelKind { get }
    var title: String { get }
    /// SF Symbol; actions without one (file formats) show their title large.
    var symbol: String? { get }
    /// Shown while the action runs, e.g. "Converting".
    var progressTitle: String { get }
    /// Whether the action writes new files (and so needs an output location).
    var producesFiles: Bool { get }
    /// Waits for the user (an editor window), so no progress is shown meanwhile.
    var isInteractive: Bool { get }

    func supports(_ types: [UTType]) -> Bool
    func perform(_ files: [URL], context: ActionContext) async throws -> ActionResult
}

extension DroviaAction {
    var sectorID: String {
        id
    }

    var symbol: String? {
        nil
    }

    var progressTitle: String {
        title
    }

    var producesFiles: Bool {
        false
    }

    var isInteractive: Bool {
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
    /// How to revert the action, beyond trashing the files it created (which the runner adds itself).
    var undo: [UndoStep] = []

    static let silent = ActionResult(showsConfirmation: false)

    /// Each result once, even when several sources went into it (a zip, a merged PDF).
    var outputs: [URL] {
        var seen: Set<URL> = []
        return processed.compactMap(\.output).filter { seen.insert($0).inserted }
    }
}

/// Everything an action needs while running.
@MainActor
struct ActionContext {
    let settings: SettingsStore
    let planner: OutputPlanner
    let shelf: ShelfController
    let reportProgress: (Double) -> Void

    /// Runs `work` for every file in parallel, reporting progress and collecting failures.
    func processEach(
        _ files: [URL],
        _ work: @escaping @Sendable (URL) async throws -> URL?
    ) async -> ActionResult {
        await processEach(files, concurrency: nil) { file, _ in try await work(file) }
    }

    /// Like `processEach(_:_:)`, for long jobs that report their own progress (0...1) per file.
    /// - Parameter concurrency: Files processed at once; defaults to one per spare CPU core.
    func processEach(
        _ files: [URL],
        concurrency: Int?,
        _ work: @escaping @Sendable (URL, _ progress: @escaping @Sendable (Double) -> Void) async throws -> URL?
    ) async -> ActionResult {
        var result = ActionResult()
        let limit = concurrency ?? max(2, ProcessInfo.processInfo.activeProcessorCount - 1)
        let tracker = ProgressTracker(fileCount: files.count, report: reportProgress)
        await withTaskGroup(of: (URL, Result<URL?, any Error>).self) { group in
            var pending = files.enumerated().makeIterator()
            func addNext() {
                guard let (index, file) = pending.next() else { return }
                group.addTask {
                    let progress: @Sendable (Double) -> Void = { fraction in
                        Task { @MainActor in tracker.update(index, fraction) }
                    }
                    do { return try await (file, .success(work(file, progress))) } catch {
                        return (file, .failure(error))
                    }
                }
            }
            for _ in 0 ..< limit {
                addNext()
            }
            for await (file, outcome) in group {
                switch outcome {
                case let .success(output):
                    result.processed.append(ProcessedFile(source: file, output: output))
                case let .failure(error):
                    result.failures.append(ActionFailure(file: file, message: error.localizedDescription))
                }
                tracker.finish(files.firstIndex(of: file) ?? 0)
                addNext()
            }
        }
        return result
    }
}

/// Combines per-file progress into one overall fraction.
@MainActor
private final class ProgressTracker {
    private var fractions: [Double]
    private let report: (Double) -> Void

    init(fileCount: Int, report: @escaping (Double) -> Void) {
        fractions = Array(repeating: 0, count: fileCount)
        self.report = report
    }

    func update(_ index: Int, _ fraction: Double) {
        // Late updates must not move a finished file backwards.
        guard fractions.indices.contains(index), fractions[index] < 1 else { return }
        fractions[index] = min(max(fraction, 0), 0.99)
        report(fractions.reduce(0, +) / Double(fractions.count))
    }

    func finish(_ index: Int) {
        guard fractions.indices.contains(index) else { return }
        fractions[index] = 1
        report(fractions.reduce(0, +) / Double(fractions.count))
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
