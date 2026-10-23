import AppKit
import SwiftUI

/// An AppKit drag source for one or more files: SwiftUI's drag APIs can't drag several files at once
/// or tell us how the drag ended.
struct FileDragSource: NSViewRepresentable {
    var urls: () -> [URL]
    var onBegin: ([URL]) -> Void = { _ in }
    var onEnd: (NSDragOperation) -> Void = { _ in }
    var onDoubleClick: () -> Void = {}
    var menu: () -> NSMenu? = { nil }

    func makeNSView(context _: Context) -> FileDragSourceView {
        FileDragSourceView()
    }

    func updateNSView(_ view: FileDragSourceView, context _: Context) {
        view.source = self
    }
}

final class FileDragSourceView: NSView, NSDraggingSource {
    var source: FileDragSource?
    private var mouseDownEvent: NSEvent?

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        if event.clickCount == 2 {
            source?.onDoubleClick()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent, let source else { return }
        let distance = hypot(
            event.locationInWindow.x - start.locationInWindow.x,
            event.locationInWindow.y - start.locationInWindow.y
        )
        guard distance > 3 else { return }
        mouseDownEvent = nil

        let urls = source.urls()
        guard !urls.isEmpty else { return }
        let items = urls.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let offset = CGFloat(min(index, 4)) * 4
            item.setDraggingFrame(NSRect(x: offset, y: -offset, width: 32, height: 32), contents: icon)
            return item
        }
        source.onBegin(urls)
        beginDraggingSession(with: items, event: event, source: self)
    }

    override func menu(for _: NSEvent) -> NSMenu? {
        source?.menu()
    }

    func draggingSession(_: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Inside Drovia (the wheel) files are only read; outside, Finder decides between copy and move.
        context == .withinApplication ? [.copy, .generic] : [.copy, .move, .generic, .link, .delete]
    }

    func draggingSession(_: NSDraggingSession, endedAt _: NSPoint, operation: NSDragOperation) {
        source?.onEnd(operation)
    }
}

/// Lets the user move the window by dragging this area.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        DragAreaView()
    }

    func updateNSView(_: NSView, context _: Context) {}

    private final class DragAreaView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
