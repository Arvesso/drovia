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
    /// The run whose progress the toast shows. Other runs wait for their summary, so parallel runs don't
    /// take turns overwriting the toast, replace a summary and its Undo button, or hide each other's toast.
    private var progressOwner: UUID?

    init(settings: SettingsStore, toast: ToastPresenter, history: HistoryStore, shelf: ShelfController) {
        self.settings = settings
        self.toast = toast
        self.history = history
        self.shelf = shelf
    }

    func run(_ action: any DroviaAction, on files: [URL]) async {
        guard !files.isEmpty else { return }
        // Files on the shelf may have been moved, renamed or trashed by this action.
        defer { shelf.pruneMissingFiles() }
        let tint = action.wheel.tint

        let run = UUID()
        let progress = ProgressBox()
        let progressTask = Task {
            guard !action.isInteractive else { return }
            try? await Task.sleep(for: Self.progressDelay)
            // Waits while another run's progress or a summary is on screen.
            while !Task.isCancelled {
                if progressOwner == nil, !toast.isVisible {
                    progressOwner = run
                    toast.showProgress(action.progressTitle, fraction: progress.fraction, tint: tint)
                    return
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
        // Ends this run's claim on the toast; true if it was showing this run's progress.
        func releaseToast() -> Bool {
            progressTask.cancel()
            guard progressOwner == run else { return false }
            progressOwner = nil
            return true
        }
        do {
            let (result, entry) = try await execute(action, on: files, allowsPrompts: true) { [weak self] fraction in
                progress.fraction = fraction
                if self?.progressOwner == run {
                    self?.toast.showProgress(action.progressTitle, fraction: fraction, tint: tint)
                }
            }
            _ = releaseToast()
            showSummary(of: result, action: action, undoable: entry)
        } catch is CancellationError {
            if releaseToast() {
                toast.hide()
            }
        } catch {
            _ = releaseToast()
            Logger.wheel.error("\(action.id) failed: \(error.localizedDescription)")
            toast.showError(String(localized: "\(action.title) failed"), detail: error.localizedDescription)
        }
    }

    /// Runs an action without any UI of its own (Shortcuts uses this): output placement, trashing
    /// originals, the shelf and history all apply. `allowsPrompts: false` never asks for a save folder.
    func execute(
        _ action: any DroviaAction,
        on files: [URL],
        allowsPrompts: Bool,
        progress: @escaping (Double) -> Void = { _ in }
    ) async throws -> (ActionResult, HistoryEntry?) {
        guard let location = await outputLocation(for: action, allowsPrompts: allowsPrompts) else {
            throw CancellationError()
        }
        let planner = OutputPlanner(location: location, template: settings.fileNameTemplate)
        let context = ActionContext(settings: settings, planner: planner, shelf: shelf, reportProgress: progress)

        var result = try await action.perform(files, context: context)
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
        return (result, record(result, of: action, fileCount: files.count))
    }

    func undo(_ entry: HistoryEntry) {
        defer { shelf.pruneMissingFiles() }
        do {
            try history.undo(entry.id)
            toast.show(
                String(localized: "Undone"),
                detail: entry.title,
                symbol: "arrow.uturn.backward.circle.fill",
                tint: .secondary
            )
        } catch UndoError.alreadyUndone {
            toast.show(
                String(localized: "Nothing to undo"),
                detail: entry.title,
                symbol: "arrow.uturn.backward.circle",
                tint: .secondary
            )
        } catch {
            toast.showError(String(localized: "Couldn't undo everything"), detail: error.localizedDescription)
        }
    }

    // MARK: - Private

    private func outputLocation(for action: any DroviaAction, allowsPrompts: Bool) async -> OutputPlanner.Location? {
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
            guard allowsPrompts else { return .nextToOriginal }
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
