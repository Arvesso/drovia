import AppKit

/// Polls modifier keys while a drag is in progress.
///
/// Reads the session-wide keyboard state from Core Graphics: it needs no permissions and, unlike
/// `NSEvent.modifierFlags`, stays current while Drovia is a background app during another app's drag.
@MainActor
final class ModifierWatcher {
    var onChange: ((WheelKind?) -> Void)?

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
        let flags = NSEvent.ModifierFlags(rawValue: UInt(CGEventSource.flagsState(.combinedSessionState).rawValue))
        let kind = WheelKind(modifiers: flags)
        guard kind != current else { return }
        current = kind
        onChange?(kind)
    }
}
