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
    private let runner: ActionRunner
    private let toast: ToastPresenter
    private lazy var panel = makePanel()

    private var showTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    /// Whether the panel is (or is about to be) on screen. Set synchronously, unlike the animated
    /// `model.isPresented`, so overlapping show and hide requests can't leave it inconsistent.
    private var isWheelShown = false
    /// Bumped on every presentation; a hide that was scheduled earlier must not hide a newer wheel.
    private var presentation = 0
    private var thumbnailTask: Task<Void, Never>?
    /// Whether the current drag comes only from allowed folders.
    private var isDragAllowed = false
    private var didWarnThisDrag = false

    init(folderAccess: FolderAccess, settings: SettingsStore, runner: ActionRunner, toast: ToastPresenter) {
        self.folderAccess = folderAccess
        self.settings = settings
        self.runner = runner
        self.toast = toast
    }

    func start() {
        dragMonitor.onStart = { [weak self] in self?.dragStarted(with: $0) }
        dragMonitor.onEnd = { [weak self] in self?.dragEnded() }
        modifierWatcher.onChange = { [weak self] in self?.modifierChanged(to: $0) }
        dragMonitor.start()
    }

    private func makePanel() -> WheelPanel {
        let panel = WheelPanel(model: model)
        panel.dropView.onHighlight = { [weak self] in self?.highlight($0) }
        panel.dropView.onDrop = { [weak self] in self?.handleDrop(at: $0, pasteboard: $1) ?? false }
        return panel
    }

    // MARK: - Drag lifecycle

    /// A drag started by Drovia itself (from the shelf), which global monitors don't report.
    /// Files on the shelf were put there by the user, so they're always allowed.
    func beginInternalDrag(with urls: [URL]) {
        dragStarted(with: DragContent(fileURLs: urls), trusted: true)
    }

    func endInternalDrag() {
        dragMonitor.resynchronize()
        dragEnded()
    }

    private func dragStarted(with content: DragContent, trusted: Bool = false) {
        // A wheel still fading out from the previous drag goes away now; this drag gets a fresh one.
        showTask?.cancel()
        hideTask?.cancel()
        if isWheelShown {
            hideWheelImmediately()
        }
        isDragAllowed = trusted || folderAccess.allows(content)
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
        guard !isWheelShown else { return }
        let delay = settings.activationDelay
        guard delay > 0 else {
            presentWheel()
            return
        }
        showTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
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
        isWheelShown = true
        presentation += 1
        let current = presentation
        model.highlighted = nil
        model.isPresented = false
        panel.present(at: NSEvent.mouseLocation, geometry: model.geometry)
        // Flip on the next run loop turn so SwiftUI animates from the hidden state.
        Task {
            guard presentation == current, isWheelShown else { return }
            model.isPresented = true
        }
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
        guard isWheelShown else { return }
        isWheelShown = false
        let current = presentation
        model.isPresented = false
        try? await Task.sleep(for: Self.hideAnimation)
        // Shown again while fading out: leave the new wheel alone.
        guard presentation == current, !isWheelShown else { return }
        panel.orderOut(nil)
        model.highlighted = nil
    }

    private func hideWheelImmediately() {
        isWheelShown = false
        presentation += 1
        model.isPresented = false
        model.highlighted = nil
        panel.orderOut(nil)
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
