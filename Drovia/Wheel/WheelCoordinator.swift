import AppKit
import os

/// Ties drag detection, modifier keys, the wheel panel and actions together.
@MainActor
final class WheelCoordinator {
    /// Releasing one modifier and pressing another briefly reports none; don't hide the wheel for that.
    private static let modifierReleaseGrace = Duration.milliseconds(150)
    /// The drop is delivered around the time of mouse up; keep the panel alive until it arrives.
    private static let dropDeliveryGrace = Duration.milliseconds(300)
    private static let hideAnimation = Duration.milliseconds(200)

    private let folderAccess: FolderAccess
    private let settings: SettingsStore
    private let dragMonitor = DragSessionMonitor()
    private let modifierWatcher = ModifierWatcher()
    private let model = WheelModel()
    private let toast = ToastPresenter()
    private lazy var runner = ActionRunner(settings: settings, toast: toast)
    private lazy var panel = makePanel()

    private var showTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var thumbnailTask: Task<Void, Never>?
    /// Whether the current drag comes only from allowed folders.
    private var isDragAllowed = false
    private var didWarnThisDrag = false

    init(folderAccess: FolderAccess, settings: SettingsStore) {
        self.folderAccess = folderAccess
        self.settings = settings
    }

    func start() {
        dragMonitor.onStart = { [weak self] in self?.dragStarted(with: $0) }
        dragMonitor.onEnd = { [weak self] in self?.dragEnded() }
        modifierWatcher.onChange = { [weak self] in self?.modifierChanged(to: $0) }
        modifierWatcher.onMouseReleased = { [weak self] in self?.dragMonitor.endSession() }
        dragMonitor.start()
    }

    private func makePanel() -> WheelPanel {
        let panel = WheelPanel(model: model)
        panel.dropView.onHighlight = { [weak self] in self?.highlight($0) }
        panel.dropView.onDrop = { [weak self] in self?.handleDrop(at: $0, pasteboard: $1) ?? false }
        return panel
    }

    // MARK: - Drag lifecycle

    private func dragStarted(with content: DragContent) {
        isDragAllowed = folderAccess.allows(content)
        didWarnThisDrag = false
        model.content = content
        model.thumbnail = nil
        model.scale = settings.wheelSize.scale
        thumbnailTask?.cancel()
        modifierWatcher.start()
        // Reading a file outside allowed folders could trigger a privacy prompt mid-drag.
        guard isDragAllowed else { return }
        thumbnailTask = Task {
            let image = await Thumbnails.image(for: content)
            guard !Task.isCancelled else { return }
            model.thumbnail = image
        }
    }

    private func dragEnded() {
        modifierWatcher.stop()
        showTask?.cancel()
        scheduleHide(after: Self.dropDeliveryGrace)
    }

    private func modifierChanged(to kind: WheelKind?) {
        showTask?.cancel()
        guard let kind else {
            if settings.hidesWheelOnModifierRelease {
                scheduleHide(after: Self.modifierReleaseGrace)
            }
            return
        }
        guard isDragAllowed else {
            warnOnce(
                String(localized: "This folder isn't allowed"),
                detail: String(localized: "Add it in Drovia Settings → Folders"),
                symbol: "folder.badge.questionmark"
            )
            return
        }
        let actions = ActionRegistry.actions(for: kind, types: model.content.contentTypes)
        guard !actions.isEmpty else {
            warnOnce(kind.emptyMessage, detail: nil, symbol: "circle.slash")
            return
        }
        hideTask?.cancel()
        let items = actions.map(\.wheelItem)
        if model.kind != kind || model.items != items {
            model.kind = kind
            model.items = items
            model.highlighted = nil
        }
        guard !model.isPresented else { return }
        let delay = settings.activationDelay
        showTask = Task {
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
            }
            presentWheel()
        }
    }

    private func warnOnce(_ title: String, detail: String?, symbol: String) {
        guard !didWarnThisDrag else { return }
        didWarnThisDrag = true
        toast.show(title, detail: detail, symbol: symbol, tint: .orange)
    }

    // MARK: - Wheel

    private func presentWheel() {
        Logger.wheel.debug("Presenting \(self.model.kind.rawValue) wheel")
        model.highlighted = nil
        panel.present(at: NSEvent.mouseLocation, geometry: model.geometry)
        // Flip on the next run loop turn so SwiftUI animates from the hidden state.
        Task { model.isPresented = true }
    }

    private func scheduleHide(after delay: Duration) {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await hideWheel()
        }
    }

    private func hideWheel() async {
        guard model.isPresented else { return }
        model.isPresented = false
        try? await Task.sleep(for: Self.hideAnimation)
        guard !model.isPresented else { return }
        panel.orderOut(nil)
        model.highlighted = nil
    }

    private func highlight(_ index: Int?) {
        guard model.highlighted != index else { return }
        model.highlighted = index
        if index != nil {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    // MARK: - Drop

    private func handleDrop(at index: Int, pasteboard: NSPasteboard) -> Bool {
        guard model.items.indices.contains(index),
              let action = ActionRegistry.action(id: model.items[index].id)
        else { return false }
        let dropped = DroppedFiles(pasteboard: pasteboard)

        hideTask?.cancel()
        hideTask = Task { await hideWheel() }

        Task {
            let files: [URL]
            do {
                files = try await dropped.resolve()
            } catch {
                Logger.wheel.error("Failed to receive dropped files: \(error.localizedDescription)")
                toast.showError(String(localized: "Couldn't receive files"), detail: error.localizedDescription)
                return
            }
            // Let the drag animation finish before menus or panels appear.
            try? await Task.sleep(for: .milliseconds(120))
            await runner.run(action, on: files)
        }
        return true
    }
}
