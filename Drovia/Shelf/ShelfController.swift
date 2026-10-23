import AppKit
import Observation
import SwiftUI

struct ShelfItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
}

@MainActor
@Observable
final class ShelfModel {
    var items: [ShelfItem] = []
}

/// A floating shelf that holds files until they're dragged somewhere else.
@MainActor
final class ShelfController {
    static let width: CGFloat = 270
    private static let rowHeight: CGFloat = 48
    private static let edgeSnapDistance: CGFloat = 60

    let model = ShelfModel()
    /// Dragging files out of the shelf, so the wheel can work with them too.
    var onDragStart: (([URL]) -> Void)?
    var onDragEnd: (() -> Void)?

    private lazy var panel = makePanel()
    private var snapTask: Task<Void, Never>?
    private var isAdjustingFrame = false

    var isVisible: Bool {
        panel.isVisible
    }

    func add(_ urls: [URL]) {
        let known = Set(model.items.map(\.url))
        model.items += urls.filter { !known.contains($0) }.map { ShelfItem(url: $0) }
        show()
    }

    func remove(_ ids: Set<ShelfItem.ID>) {
        model.items.removeAll { ids.contains($0.id) }
        if model.items.isEmpty {
            hide()
        } else {
            updateFrame()
        }
    }

    func clear() {
        model.items.removeAll()
        hide()
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        if !panel.isVisible {
            placeInitially()
        }
        updateFrame()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// Drops items whose files were moved or deleted elsewhere.
    func pruneMissingFiles() {
        let missing = model.items.filter { !FileManager.default.fileExists(atPath: $0.url.path) }
        if !missing.isEmpty {
            remove(Set(missing.map(\.id)))
        }
    }

    // MARK: - Window

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: ShelfView(model: model, controller: self))
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.scheduleEdgeSnap() }
        }
        return panel
    }

    private var preferredHeight: CGFloat {
        let rows = CGFloat(max(1, min(model.items.count, 6)))
        return 52 + rows * Self.rowHeight + 12
    }

    /// Resizes to fit the items, keeping the top edge in place.
    private func updateFrame() {
        var frame = panel.frame
        let top = frame.maxY
        frame.size = CGSize(width: Self.width, height: preferredHeight)
        frame.origin.y = top - frame.height
        setFrame(frame)
    }

    private func placeInitially() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let height = preferredHeight
        setFrame(NSRect(
            x: visible.maxX - Self.width - 12,
            y: visible.midY - height / 2,
            width: Self.width,
            height: height
        ))
    }

    private func setFrame(_ frame: NSRect) {
        isAdjustingFrame = true
        panel.setFrame(frame, display: true, animate: false)
        isAdjustingFrame = false
    }

    /// After the user stops moving the shelf near a screen edge, pin it to that edge.
    private func scheduleEdgeSnap() {
        guard !isAdjustingFrame else { return }
        snapTask?.cancel()
        snapTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let visible = panel.screen?.visibleFrame else { return }
            var frame = panel.frame
            if frame.minX - visible.minX < Self.edgeSnapDistance {
                frame.origin.x = visible.minX + 12
            } else if visible.maxX - frame.maxX < Self.edgeSnapDistance {
                frame.origin.x = visible.maxX - frame.width - 12
            }
            frame.origin.y = min(max(frame.origin.y, visible.minY + 12), visible.maxY - frame.height - 12)
            guard frame != panel.frame else { return }
            isAdjustingFrame = true
            panel.animator().setFrame(frame, display: true)
            isAdjustingFrame = false
        }
    }
}
