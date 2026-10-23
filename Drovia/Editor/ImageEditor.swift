import AppKit
import SwiftUI

/// Opens the editor window for a set of images and returns the edited ones when it closes.
@MainActor
final class ImageEditor: NSObject, NSWindowDelegate {
    /// Editors stay alive while their window is open.
    private static var open: [ImageEditor] = []

    private let model: EditorModel
    private let window: NSWindow

    static func edit(_ files: [URL], mode: EditorMode, redaction: RedactionStyle) async -> [EditedImage] {
        await withCheckedContinuation { continuation in
            let editor = ImageEditor(files: files, mode: mode, redaction: redaction) {
                continuation.resume(returning: $0)
            }
            open.append(editor)
            editor.show()
        }
    }

    private init(
        files: [URL],
        mode: EditorMode,
        redaction: RedactionStyle,
        completion: @escaping ([EditedImage]) -> Void
    ) {
        model = EditorModel(files: files, mode: mode, redaction: redaction)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 740),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.contentViewController = NSHostingController(rootView: EditorView(model: model))
        window.setContentSize(NSSize(width: 1040, height: 740))
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.delegate = self
        window.title = files[0].lastPathComponent
        model.onFinish = { [weak self] results in
            self?.close()
            completion(results)
        }
        withObservationTracking { _ = model.index } onChange: { [weak self] in
            Task { @MainActor in self?.updateTitle() }
        }
    }

    private func show() {
        // Center on the screen with the pointer, where the files were dropped.
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            let frame = window.frame
            let visible = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2))
        } else {
            window.center()
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func updateTitle() {
        window.title = model.source.lastPathComponent
        withObservationTracking { _ = model.index } onChange: { [weak self] in
            Task { @MainActor in self?.updateTitle() }
        }
    }

    private func close() {
        window.delegate = nil
        window.close()
        Self.open.removeAll { $0 === self }
    }

    func windowWillClose(_: Notification) {
        // Closing the window keeps whatever was already saved.
        model.finish()
    }
}
