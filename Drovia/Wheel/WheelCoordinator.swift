import AppKit
import os

/// Ties drag detection, modifier keys and the wheel panel together.
@MainActor
final class WheelCoordinator {
    /// Releasing one modifier and pressing another briefly reports none; don't hide the wheel for that.
    private static let modifierReleaseGrace = Duration.milliseconds(150)
    /// The drop is delivered around the time of mouse up; keep the panel alive until it arrives.
    private static let dropDeliveryGrace = Duration.milliseconds(300)
    private static let hideAnimation = Duration.milliseconds(200)

    private let folderAccess: FolderAccess
    private let dragMonitor = DragSessionMonitor()
    private let modifierWatcher = ModifierWatcher()
    private let model = WheelModel()
    private let toast = ToastPresenter()
    private lazy var panel = makePanel()

    private var hideTask: Task<Void, Never>?
    private var thumbnailTask: Task<Void, Never>?
    /// Whether the current drag comes only from allowed folders.
    private var isDragAllowed = false
    private var didWarnAboutFolder = false

    init(folderAccess: FolderAccess) {
        self.folderAccess = folderAccess
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
        didWarnAboutFolder = false
        model.content = content
        model.thumbnail = nil
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
        scheduleHide(after: Self.dropDeliveryGrace)
    }

    private func modifierChanged(to kind: WheelKind?) {
        guard let kind else {
            scheduleHide(after: Self.modifierReleaseGrace)
            return
        }
        guard isDragAllowed else {
            warnAboutFolderOnce()
            return
        }
        hideTask?.cancel()
        if model.kind != kind || model.items.isEmpty {
            model.kind = kind
            model.items = WheelCatalog.items(for: kind)
            model.highlighted = nil
        }
        if !model.isPresented {
            presentWheel()
        }
    }

    private func warnAboutFolderOnce() {
        guard !didWarnAboutFolder else { return }
        didWarnAboutFolder = true
        toast.show(
            String(localized: "This folder isn't allowed"),
            subtitle: String(localized: "Add it in Drovia Settings → Folders"),
            symbol: "folder.badge.questionmark",
            tint: .orange
        )
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
        guard model.items.indices.contains(index) else { return false }
        let item = model.items[index]
        let kind = model.kind
        let dropped = DroppedFiles(pasteboard: pasteboard)

        hideTask?.cancel()
        hideTask = Task { await hideWheel() }

        Task {
            do {
                let urls = try await dropped.resolve()
                Logger.wheel.info("\(kind.rawValue) → \(item.id): \(urls.map(\.lastPathComponent))")
                toast.show(
                    "\(kind.title) · \(item.title)",
                    subtitle: String(localized: "\(urls.count) files"),
                    tint: kind.tint
                )
            } catch {
                Logger.wheel.error("Failed to receive dropped files: \(error.localizedDescription)")
                toast.show(
                    String(localized: "Couldn't receive files"),
                    subtitle: error.localizedDescription,
                    symbol: "exclamationmark.triangle.fill",
                    tint: .orange
                )
            }
        }
        return true
    }
}
