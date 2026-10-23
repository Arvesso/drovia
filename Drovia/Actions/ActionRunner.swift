import AppKit
import os

/// Runs an action on dropped files, with progress, a summary toast, history and undo.
@MainActor
final class ActionRunner {
    /// Quick actions finish without ever showing progress.
    private static let progressDelay = Duration.milliseconds(400)

    private let settings: SettingsStore
    private let toast: ToastPresenter
    private let history: HistoryStore
    private let shelf: ShelfController

    init(settings: SettingsStore, toast: ToastPresenter, history: HistoryStore, shelf: ShelfController) {
        self.settings = settings
        self.toast = toast
        self.history = history
        self.shelf = shelf
    }

    func run(_ action: any DroviaAction, on files: [URL]) async {
        guard !files.isEmpty else { return }
        let tint = action.wheel.tint

        guard let location = await outputLocation(for: action) else { return }
        let planner = OutputPlanner(location: location, template: settings.fileNameTemplate)

        let progress = ProgressBox()
        let progressTask = Task {
            try? await Task.sleep(for: Self.progressDelay)
            guard !Task.isCancelled else { return }
            toast.showProgress(action.progressTitle, fraction: progress.fraction, tint: tint)
        }
        let context = ActionContext(settings: settings, planner: planner, shelf: shelf) { [toast] fraction in
            progress.fraction = fraction
            if toast.isShowingProgress {
                toast.showProgress(action.progressTitle, fraction: fraction, tint: tint)
            }
        }

        do {
            var result = try await action.perform(files, context: context)
            progressTask.cancel()
            Logger.wheel.info("\(action.id): \(result.outputs.count) output(s), \(result.failures.count) failure(s)")
            if action.producesFiles {
                result.undo += result.outputs.map(UndoStep.trashCreated)
                if settings.trashesOriginals {
                    result.undo += trashOriginals(of: result)
                }
                if settings.addsResultsToShelf, !result.outputs.isEmpty {
                    shelf.add(result.outputs)
                }
            }
            let entry = record(result, of: action, fileCount: files.count)
            showSummary(of: result, action: action, undoable: entry)
        } catch is CancellationError {
            progressTask.cancel()
            toast.hide()
        } catch {
            progressTask.cancel()
            Logger.wheel.error("\(action.id) failed: \(error.localizedDescription)")
            toast.showError(String(localized: "\(action.title) failed"), detail: error.localizedDescription)
        }
    }

    func undo(_ entry: HistoryEntry) {
        do {
            try history.undo(entry.id)
            toast.show(
                String(localized: "Undone"),
                detail: entry.title,
                symbol: "arrow.uturn.backward.circle.fill",
                tint: .secondary
            )
        } catch {
            toast.showError(String(localized: "Couldn't undo everything"), detail: error.localizedDescription)
        }
    }

    // MARK: - Private

    private func outputLocation(for action: any DroviaAction) async -> OutputPlanner.Location? {
        guard action.producesFiles else { return .nextToOriginal }
        switch settings.outputLocation {
        case .nextToOriginal:
            return .nextToOriginal
        case .folder:
            if let path = settings.outputFolderPath {
                return .folder(URL(fileURLWithPath: path, isDirectory: true))
            }
            return .nextToOriginal
        case .ask:
            return await FolderPanel.choose(prompt: String(localized: "Save Here")).map { .folder($0) }
        }
    }

    private func trashOriginals(of result: ActionResult) -> [UndoStep] {
        result.processed.filter { $0.output != nil }.compactMap { file in
            var trashed: NSURL?
            do {
                try FileManager.default.trashItem(at: file.source, resultingItemURL: &trashed)
            } catch {
                Logger.wheel.error("Couldn't trash \(file.source.lastPathComponent): \(error.localizedDescription)")
            }
            return (trashed as URL?).map { .restore(trashed: $0, original: file.source) }
        }
    }

    /// Only operations that changed files are worth keeping in history.
    private func record(_ result: ActionResult, of action: any DroviaAction, fileCount: Int) -> HistoryEntry? {
        guard !result.undo.isEmpty else { return nil }
        let title = fileCount == 1
            ? "\(action.title) · \(result.processed.first?.source.lastPathComponent ?? "")"
            : "\(action.title) · \(String(localized: "\(fileCount) files"))"
        return history.add(title: title, symbol: action.symbol ?? "doc", outputs: result.outputs, undo: result.undo)
    }

    private func showSummary(of result: ActionResult, action: any DroviaAction, undoable entry: HistoryEntry?) {
        guard result.showsConfirmation else {
            toast.hide()
            return
        }
        let tint = action.wheel.tint
        let outputs = result.outputs
        let undo: (() -> Void)? = entry.map { entry in { [weak self] in self?.undo(entry) } }

        if !result.failures.isEmpty {
            let total = result.processed.count + result.failures.count
            let title = outputs.isEmpty
                ? String(localized: "\(action.title) failed")
                : String(localized: "\(outputs.count) of \(total) done")
            toast.showError(title, detail: result.failures.first?.message, reveal: outputs)
            return
        }

        if let message = result.message {
            toast.show(message, detail: result.detail, tint: tint, reveal: outputs, undo: undo)
        } else if outputs.count == 1, let processed = result.processed.first(where: { $0.output != nil }),
                  let output = processed.output
        {
            toast.show(
                output.lastPathComponent,
                detail: Self.sizeChange(from: processed.source, to: output),
                tint: tint,
                reveal: outputs,
                undo: undo
            )
        } else if outputs.isEmpty {
            toast.show(String(localized: "Nothing to change"), detail: nil, tint: tint)
        } else {
            toast.show(
                String(localized: "\(outputs.count) files done"),
                detail: String(localized: "Click to show in Finder"),
                tint: tint,
                reveal: outputs,
                undo: undo
            )
        }
    }

    /// "1.2 MB → 340 KB (−72%)", or just the new size.
    static func sizeChange(from source: URL, to output: URL) -> String? {
        guard let after = output.fileSize else { return nil }
        let style = ByteCountFormatStyle(style: .file)
        let afterText = Int64(after).formatted(style)
        guard let before = source.fileSize, before > 0, !output.hasDirectoryPath else { return afterText }
        let change = Double(after - before) / Double(before)
        let percent = change.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always()))
        return "\(Int64(before).formatted(style)) → \(afterText) (\(percent))"
    }
}

@MainActor
private final class ProgressBox {
    var fraction = 0.0
}
