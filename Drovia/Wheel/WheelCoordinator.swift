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
    /// The wheel last used from the keyboard, opened first next time.
    private var lastKeyboardKind = WheelKind.convert
    private var thumbnailTask: Task<Void, Never>?
    private var isReadingFinderSelection = false
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
        panel.dropView.onKey = { [weak self] in self?.handleKey($0) ?? false }
        panel.dropView.onClick = { [weak self] in self?.handleClick(at: $0) }
        NotificationCenter.default
            .addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) {
                [weak self] _ in
                // Clicking anywhere else closes a keyboard-opened wheel.
                MainActor.assumeIsolated {
                    if self?.model.isKeyboardMode == true {
                        self?.hideWheelImmediately()
                    }
                }
            }
        return panel
    }

    // MARK: - Drag lifecycle

    /// A drag started by Drovia itself (from the shelf), which global monitors don't report.
    /// Files on the shelf were put there by the user, so they're always allowed.
    func beginInternalDrag(with urls: [URL]) {
        dragMonitor.beginInternalDrag()
        dragStarted(with: DragContent(fileURLs: urls), trusted: true)
    }

    func endInternalDrag() {
        dragMonitor.endInternalDrag()
        dragEnded()
    }

    private func dragStarted(with content: DragContent, trusted: Bool = false) {
        // The app being dragged from is frontmost; some apps are set to be left alone.
        if !trusted, let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           settings.excludedApps.contains(app)
        {
            Logger.drag.debug("Ignoring drag from excluded app \(app)")
            return
        }
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
        thumbnailTask = nil
        modifierWatcher.start()
    }

    /// Most drags never show the wheel, so the preview is only made once a modifier is held.
    private func loadThumbnailIfNeeded() {
        guard thumbnailTask == nil else { return }
        let content = model.content
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
        // Reading a file outside allowed folders could trigger a privacy prompt mid-drag.
        guard isDragAllowed else {
            warnOnce(
                String(localized: "This folder isn't allowed"),
                detail: String(localized: "Add it in Drovia Settings → Folders"),
                symbol: "folder.badge.questionmark"
            )
            return
        }
        loadThumbnailIfNeeded()
        let actions = ActionRegistry.actions(
            for: kind,
            types: model.content.contentTypes,
            layout: settings.wheelLayout,
            recipes: settings.recipes
        )
        guard !actions.isEmpty else {
            // The previous wheel would otherwise stay up and accept a drop meant for this one.
            if isWheelShown {
                hideWheelImmediately()
            }
            warnOnce(
                kind.emptyMessage,
                detail: kind == .recipes ? String(localized: "Create one in Settings → Recipes") : nil,
                symbol: "circle.slash"
            )
            return
        }
        hideTask?.cancel()
        let items = actions.map(\.wheelItem)
        if model.kind != kind || model.items != items {
            model.kind = kind
            model.items = items
            model.highlighted = nil
            if isWheelShown {
                panel.update(geometry: model.geometry)
            }
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
        endKeyboardMode()
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
        endKeyboardMode()
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

    // MARK: - Keyboard

    /// Opens the wheel at the pointer for the files selected in Finder.
    func openForFinderSelection() async {
        // A second press while Finder is still answering the first would open two wheels.
        guard !isReadingFinderSelection else { return }
        isReadingFinderSelection = true
        defer { isReadingFinderSelection = false }
        let urls: [URL]
        do {
            urls = try await FinderSelection.selectedFiles()
        } catch FinderSelection.Failure.notAllowed {
            toast.show(
                String(localized: "Drovia can't see Finder's selection"),
                detail: String(localized: "Allow it in Settings → General → Keyboard"),
                symbol: "lock.fill",
                tint: .orange
            )
            return
        } catch {
            toast.showError(String(localized: "Couldn't read Finder's selection"), detail: error.localizedDescription)
            return
        }
        guard !urls.isEmpty else {
            toast.show(
                String(localized: "Select files in Finder first"),
                detail: nil,
                symbol: "cursorarrow.click.2",
                tint: .secondary
            )
            return
        }
        let content = DragContent(fileURLs: urls)
        guard folderAccess.allows(content) else {
            toast.show(
                String(localized: "This folder isn't allowed"),
                detail: String(localized: "Add it in Drovia Settings → Folders"),
                symbol: "folder.badge.questionmark",
                tint: .orange
            )
            return
        }

        let types = content.contentTypes
        let available = WheelKind.allCases.filter {
            !ActionRegistry.actions(for: $0, types: types, layout: settings.wheelLayout, recipes: settings.recipes)
                .isEmpty
        }
        guard let kind = available.contains(lastKeyboardKind) ? lastKeyboardKind : available.first else {
            toast.show(
                String(localized: "No actions for these files"),
                detail: nil,
                symbol: "circle.slash",
                tint: .orange
            )
            return
        }

        showTask?.cancel()
        hideTask?.cancel()
        if isWheelShown {
            hideWheelImmediately()
        }
        model.content = content
        model.thumbnail = nil
        model.scale = settings.wheelSize.scale
        model.availableKinds = available
        thumbnailTask?.cancel()
        thumbnailTask = Task {
            let image = await Thumbnails.image(for: content)
            guard !Task.isCancelled else { return }
            model.thumbnail = image
        }
        switchKeyboardWheel(to: kind)
        model.isKeyboardMode = true
        panel.acceptsKeyboard = true
        presentWheel()
        model.highlighted = 0
        panel.makeKey()
        panel.makeFirstResponder(panel.dropView)
    }

    private func switchKeyboardWheel(to kind: WheelKind) {
        lastKeyboardKind = kind
        model.kind = kind
        model.items = ActionRegistry.actions(
            for: kind,
            types: model.content.contentTypes,
            layout: settings.wheelLayout,
            recipes: settings.recipes
        )
        .map(\.wheelItem)
        model.highlighted = model.items.isEmpty ? nil : 0
        // Another wheel can have more sectors and so a bigger ring.
        panel.update(geometry: model.geometry)
    }

    /// Key codes of 1–9 on the number row and the keypad.
    private static let digitKeys: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
        83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9,
    ]

    private func handleKey(_ event: NSEvent) -> Bool {
        guard model.isKeyboardMode else { return false }
        let count = model.items.count
        switch event.keyCode {
        case 53: // Esc
            hideWheelImmediately()
        case 48: // Tab, ⇧Tab
            let kinds = model.availableKinds
            guard let index = kinds.firstIndex(of: model.kind), !kinds.isEmpty else { return true }
            let step = event.modifierFlags.contains(.shift) ? kinds.count - 1 : 1
            switchKeyboardWheel(to: kinds[(index + step) % kinds.count])
        case 123, 126: // ← ↑
            highlight(((model.highlighted ?? 0) - 1 + count) % max(count, 1))
        case 124, 125: // → ↓
            highlight(((model.highlighted ?? -1) + 1) % max(count, 1))
        case 36, 76, 49: // Return, Enter, Space
            if let index = model.highlighted {
                runKeyboardSelection(index)
            }
        default:
            // By key position, so the number row works on layouts like AZERTY where it types other characters.
            guard let digit = Self.digitKeys[event.keyCode], digit <= count else {
                return false
            }
            runKeyboardSelection(digit - 1)
        }
        return true
    }

    private func handleClick(at index: Int?) {
        guard model.isKeyboardMode else { return }
        if let index {
            runKeyboardSelection(index)
        } else {
            hideWheelImmediately()
        }
    }

    private func runKeyboardSelection(_ index: Int) {
        guard model.items.indices.contains(index), let action = ActionRegistry.action(
            id: model.items[index].id,
            recipes: settings.recipes
        ) else {
            return
        }
        let files = model.content.fileURLs
        hideWheelImmediately()
        Task { await runner.run(action, on: files) }
    }

    private func endKeyboardMode() {
        model.isKeyboardMode = false
        panel.acceptsKeyboard = false
    }

    // MARK: - Drop

    private func handleDrop(at index: Int, pasteboard: NSPasteboard) -> Bool {
        guard model.items.indices.contains(index),
              let action = ActionRegistry.action(id: model.items[index].id, recipes: settings.recipes)
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
