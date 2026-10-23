import AppKit

/// Polls modifier keys and the mouse button while a drag is in progress.
///
/// Polling `NSEvent.modifierFlags` needs no Accessibility or Input Monitoring permission,
/// unlike a global key-event monitor.
@MainActor
final class ModifierWatcher {
    var onChange: ((WheelKind?) -> Void)?
    var onMouseReleased: (() -> Void)?

    private var timer: Timer?
    private var current: WheelKind?

    func start() {
        stop()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        current = nil
    }

    private func tick() {
        // Safety net in case the global mouse-up event was missed.
        if NSEvent.pressedMouseButtons & 1 == 0 {
            onMouseReleased?()
            return
        }
        let kind = WheelKind(modifiers: NSEvent.modifierFlags)
        guard kind != current else { return }
        current = kind
        onChange?(kind)
    }
}
