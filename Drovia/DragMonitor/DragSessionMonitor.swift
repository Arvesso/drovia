import AppKit
import os

/// Detects file drags anywhere on screen.
///
/// A drag is recognized when the drag pasteboard has changed since the previous mouse up and contains files.
/// The baseline is taken at mouse up rather than mouse down: global events arrive asynchronously, and when
/// dragging an already selected file Finder writes the pasteboard before our mouse-down handler runs.
/// Global mouse monitors need no special permissions.
@MainActor
final class DragSessionMonitor {
    var onStart: ((DragContent) -> Void)?
    var onEnd: (() -> Void)?

    private(set) var isDragging = false
    private var monitors: [Any] = []
    private var baselineChangeCount = 0
    private let pasteboard = NSPasteboard(name: .drag)

    func start() {
        guard monitors.isEmpty else { return }
        baselineChangeCount = pasteboard.changeCount
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handle(type) }
        }) {
            monitors.append(monitor)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        endSession()
    }

    func endSession() {
        guard isDragging else { return }
        isDragging = false
        Logger.drag.debug("Drag ended")
        onEnd?()
    }

    private func handle(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown:
            endSession()
        case .leftMouseDragged:
            let changeCount = pasteboard.changeCount
            guard !isDragging, changeCount != baselineChangeCount else { return }
            baselineChangeCount = changeCount
            let content = DragContent(pasteboard: pasteboard)
            guard !content.isEmpty else { return }
            isDragging = true
            Logger.drag.debug("Drag started with \(content.itemCount) item(s)")
            onStart?(content)
        case .leftMouseUp:
            endSession()
            baselineChangeCount = pasteboard.changeCount
        default:
            break
        }
    }
}
