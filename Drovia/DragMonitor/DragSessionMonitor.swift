import AppKit
import os

/// Detects file drags anywhere on screen, without Accessibility or Input Monitoring permissions.
///
/// Global mouse events only start a press: from mouse down until the button is released, a timer polls the
/// drag pasteboard. A drag is recognized once its change count differs from the one left by the previous press
/// *and* it holds files. Polling matters because global `leftMouseDragged` events are unreliable once another
/// app's drag session is running, and the source app may clear the pasteboard before it writes the files.
@MainActor
final class DragSessionMonitor {
    /// Reads of a new pasteboard generation that came back empty before we treat it as "not a file drag".
    /// Apps clear the pasteboard first and write items a moment later.
    private static let emptyReadsBeforeGivingUp = 30
    /// Consecutive "button up" readings that end a press, so one glitchy sample doesn't cut a drag short.
    private static let releasedReadingsToEnd = 2

    var onStart: ((DragContent) -> Void)?
    var onEnd: (() -> Void)?

    private(set) var isDragging = false
    private let pasteboard = NSPasteboard(name: .drag)
    private var monitors: [Any] = []
    private var pollTimer: Timer?
    /// Catches a press whose mouse-down event never reached us.
    private var fallbackTimer: Timer?
    /// Keeps App Nap from throttling the poll timer while the button is down.
    private var activity: (any NSObjectProtocol)?

    /// Change count left by the last finished press (or our own drag); a new drag must differ from it.
    private var settledChangeCount = 0
    /// Change count already examined during this press and found to hold no files.
    private var rejectedChangeCount: Int?
    /// Change count whose empty reads are being counted.
    private var pendingChangeCount: Int?
    private var emptyReads = 0
    private var releasedReadings = 0

    func start() {
        guard monitors.isEmpty else { return }
        settledChangeCount = pasteboard.changeCount
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handle(type) }
        }) {
            monitors.append(monitor)
        }
        let fallback = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                if CGEventSource.buttonState(.combinedSessionState, button: .left) {
                    self?.startPolling()
                }
            }
        }
        RunLoop.main.add(fallback, forMode: .common)
        fallbackTimer = fallback
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        finishPress()
    }

    /// Call after Drovia itself wrote the drag pasteboard (dragging from the shelf), which global monitors
    /// don't see, so that drag isn't mistaken for a new one later.
    func resynchronize() {
        settledChangeCount = pasteboard.changeCount
    }

    // MARK: - Events

    private func handle(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown, .leftMouseDragged:
            startPolling()
        case .leftMouseUp:
            finishPress()
        default:
            break
        }
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        rejectedChangeCount = nil
        pendingChangeCount = nil
        emptyReads = 0
        releasedReadings = 0
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Watching a mouse press for file drags"
        )
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        poll()
    }

    private func poll() {
        guard CGEventSource.buttonState(.combinedSessionState, button: .left) else {
            releasedReadings += 1
            if releasedReadings >= Self.releasedReadingsToEnd {
                finishPress()
            }
            return
        }
        releasedReadings = 0
        guard !isDragging else { return }

        let changeCount = pasteboard.changeCount
        guard changeCount != settledChangeCount, changeCount != rejectedChangeCount else { return }

        let content = DragContent(pasteboard: pasteboard)
        guard !content.isEmpty else {
            if pendingChangeCount != changeCount {
                pendingChangeCount = changeCount
                emptyReads = 0
            }
            emptyReads += 1
            if emptyReads >= Self.emptyReadsBeforeGivingUp {
                Logger.drag.debug("Pasteboard \(changeCount) holds no files; ignoring this drag")
                rejectedChangeCount = changeCount
            }
            return
        }
        isDragging = true
        Logger.drag
            .debug(
                "Drag started: \(content.itemCount) item(s), pasteboard \(changeCount), \(self.emptyReads) empty read(s)"
            )
        onStart?(content)
    }

    /// The button is up: end the drag if there was one, and settle the change count for the next press.
    private func finishPress() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        settledChangeCount = pasteboard.changeCount
        guard isDragging else { return }
        isDragging = false
        Logger.drag.debug("Drag ended")
        onEnd?()
    }
}
