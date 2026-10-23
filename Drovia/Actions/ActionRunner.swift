import AppKit
import os

/// Runs an action on dropped files, with progress and a summary toast.
@MainActor
final class ActionRunner {
    /// Quick actions finish without ever showing progress.
    private static let progressDelay = Duration.milliseconds(400)

    private let settings: SettingsStore
    private let toast: ToastPresenter

    init(settings: SettingsStore, toast: ToastPresenter) {
        self.settings = settings
        self.toast = toast
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
        let context = ActionContext(settings: settings, planner: planner) { [toast] fraction in
            progress.fraction = fraction
            if toast.isShowingProgress {
                toast.showProgress(action.progressTitle, fraction: fraction, tint: tint)
            }
        }

        do {
            let result = try await action.perform(files, context: context)
            progressTask.cancel()
            Logger.wheel.info("\(action.id): \(result.outputs.count) output(s), \(result.failures.count) failure(s)")
            if action.producesFiles, settings.trashesOriginals {
                trashOriginals(of: result)
            }
            showSummary(of: result, action: action)
        } catch is CancellationError {
            progressTask.cancel()
            toast.hide()
        } catch {
            progressTask.cancel()
            Logger.wheel.error("\(action.id) failed: \(error.localizedDescription)")
            toast.showError(String(localized: "\(action.title) failed"), detail: error.localizedDescription)
        }
    }

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

    private func trashOriginals(of result: ActionResult) {
        for file in result.processed where file.output != nil {
            do {
                try FileManager.default.trashItem(at: file.source, resultingItemURL: nil)
            } catch {
                Logger.wheel.error("Couldn't trash \(file.source.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    private func showSummary(of result: ActionResult, action: any DroviaAction) {
        guard result.showsConfirmation else {
            toast.hide()
            return
        }
        let tint = action.wheel.tint
        let outputs = result.outputs

        if !result.failures.isEmpty {
            let total = result.processed.count + result.failures.count
            let title = outputs.isEmpty
                ? String(localized: "\(action.title) failed")
                : String(localized: "\(outputs.count) of \(total) done")
            toast.showError(title, detail: result.failures.first?.message, reveal: outputs)
            return
        }

        if let message = result.message {
            toast.show(message, detail: result.detail, tint: tint, reveal: outputs)
        } else if outputs.count == 1, let processed = result.processed.first(where: { $0.output != nil }),
                  let output = processed.output
        {
            toast.show(
                output.lastPathComponent,
                detail: Self.sizeChange(from: processed.source, to: output),
                tint: tint,
                reveal: outputs
            )
        } else if outputs.isEmpty {
            toast.show(String(localized: "Nothing to change"), detail: nil, tint: tint)
        } else {
            toast.show(
                String(localized: "\(outputs.count) files done"),
                detail: String(localized: "Click to show in Finder"),
                tint: tint,
                reveal: outputs
            )
        }
    }

    /// "1.2 MB → 340 KB (−72%)", or just the new size.
    static func sizeChange(from source: URL, to output: URL) -> String? {
        guard let after = output.fileSize else { return nil }
        let style = ByteCountFormatStyle(style: .file)
        let afterText = Int64(after).formatted(style)
        guard let before = source.fileSize, before > 0 else { return afterText }
        let change = Double(after - before) / Double(before)
        let percent = change.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always()))
        return "\(Int64(before).formatted(style)) → \(afterText) (\(percent))"
    }
}

@MainActor
private final class ProgressBox {
    var fraction = 0.0
}
