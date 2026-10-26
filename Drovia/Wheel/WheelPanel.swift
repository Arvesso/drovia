import AppKit
import SwiftUI

/// Borderless, non-activating panel that hosts the wheel above every app, Space and full-screen window.
final class WheelPanel: NSPanel {
    let dropView: WheelDropView

    init(model: WheelModel) {
        dropView = WheelDropView(model: model)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        // Set explicitly so transparent areas still receive mouse and drag events.
        ignoresMouseEvents = false

        let container = NSView()
        let hostingView = NSHostingView(rootView: WheelView(model: model))
        hostingView.sizingOptions = []
        for view in [hostingView, dropView] {
            view.autoresizingMask = [.width, .height]
            container.addSubview(view)
        }
        contentView = container
    }

    /// In keyboard mode the panel takes key focus (without activating Drovia) to receive key presses.
    var acceptsKeyboard = false

    override var canBecomeKey: Bool {
        acceptsKeyboard
    }

    override var canBecomeMain: Bool {
        false
    }

    /// Shows the panel centered on `point` (screen coordinates), keeping the wheel itself on screen.
    func present(at point: NSPoint, geometry: WheelGeometry) {
        let side = geometry.panelSide
        var center = point
        // The pointer can sit exactly on a screen's top edge, which NSMouseInRect counts as outside.
        let screen = NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(point) } ?? NSScreen.main
        if let screen {
            // In keyboard mode the key hints sit below the ring.
            let reach = geometry.outerRadius + (acceptsKeyboard ? 64 : 0)
            let visible = screen.visibleFrame.insetBy(dx: reach, dy: reach)
            center.x = min(max(center.x, visible.minX), visible.maxX)
            center.y = min(max(center.y, visible.minY), visible.maxY)
        }
        setFrame(NSRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side), display: true)
        contentView?.subviews.forEach { $0.frame = contentView?.bounds ?? .zero }
        orderFrontRegardless()
    }

    /// Resizes a shown panel for a wheel with a different number of sectors, around the same center.
    func update(geometry: WheelGeometry) {
        guard isVisible, frame.width != geometry.panelSide else { return }
        present(at: NSPoint(x: frame.midX, y: frame.midY), geometry: geometry)
    }
}
