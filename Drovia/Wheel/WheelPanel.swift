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
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) {
            let visible = screen.visibleFrame.insetBy(dx: geometry.outerRadius, dy: geometry.outerRadius)
            center.x = min(max(center.x, visible.minX), visible.maxX)
            center.y = min(max(center.y, visible.minY), visible.maxY)
        }
        setFrame(NSRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side), display: true)
        contentView?.subviews.forEach { $0.frame = contentView?.bounds ?? .zero }
        orderFrontRegardless()
    }
}
