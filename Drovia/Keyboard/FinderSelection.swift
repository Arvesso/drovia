import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let showWheel = Self("showWheel", initial: .init(.d, modifiers: [.control, .option]))
}

/// Reads Finder's selection through Apple Events (needs the user's Automation consent once).
enum FinderSelection {
    enum Failure: LocalizedError {
        case notAllowed
        case scriptFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAllowed: String(localized: "Drovia isn't allowed to control Finder")
            case let .scriptFailed(message): message
            }
        }
    }

    /// One path per line. A busy Finder (a stalled network volume, a big copy) gets a few seconds, not the
    /// default two minutes.
    private static let script = """
    with timeout of 5 seconds
        tell application "Finder"
            set picked to selection as alias list
            set paths to {}
            repeat with item_ in picked
                set end of paths to POSIX path of (item_ as alias)
            end repeat
        end tell
    end timeout
    set AppleScript's text item delimiters to linefeed
    return paths as text
    """

    /// Runs in `osascript`, off the main thread: NSAppleScript must run on it and would freeze the app while
    /// waiting for Finder. macOS attributes the Apple Events to Drovia, so its Automation consent applies.
    static func selectedFiles() async throws -> [URL] {
        let result = try await Subprocess.run("/usr/bin/osascript", ["-e", script])
        guard result.status == 0 else {
            let message = result.errorMessage ?? "osascript exited with \(result.status)"
            if message.contains("(-1743)") {
                throw Failure.notAllowed
            }
            throw Failure.scriptFailed(message)
        }
        return String(decoding: result.standardOutput, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { URL(fileURLWithPath: String($0)) }
    }
}

/// Whether Drovia may send Apple Events to Finder.
enum FinderAutomation {
    enum Status {
        case allowed, denied, undetermined, finderNotRunning
    }

    /// With `ask`, macOS shows its consent prompt if the user hasn't decided yet; that call blocks until they do.
    nonisolated static func status(ask: Bool) -> Status {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
        guard let desc = target.aeDesc else { return .undetermined }
        let result = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask)
        switch result {
        case noErr: return .allowed
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(procNotFound): return .finderNotRunning
        default: return .undetermined
        }
    }

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
}
