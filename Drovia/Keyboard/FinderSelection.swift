import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let showWheel = Self("showWheel", initial: .init(.d, modifiers: [.control, .option]))
}

/// Reads Finder's selection through Apple Events (needs the user's Automation consent once).
@MainActor
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

    private static let script = """
    tell application "Finder"
        set picked to selection as alias list
        set paths to {}
        repeat with item_ in picked
            set end of paths to POSIX path of (item_ as alias)
        end repeat
        return paths
    end tell
    """

    static func selectedFiles() throws -> [URL] {
        var error: NSDictionary?
        guard let result = NSAppleScript(source: script)?.executeAndReturnError(&error) else {
            let code = error?[NSAppleScript.errorNumber] as? Int
            if code == -1743 {
                throw Failure.notAllowed
            }
            throw Failure.scriptFailed(error?[NSAppleScript.errorMessage] as? String ?? "AppleScript error")
        }
        guard result.numberOfItems > 0 else { return [] }
        return (1 ... result.numberOfItems).compactMap { result.atIndex($0)?.stringValue }
            .map { URL(fileURLWithPath: $0) }
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
