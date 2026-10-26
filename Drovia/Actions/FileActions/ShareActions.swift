import AppKit
import UniformTypeIdentifiers

struct AirDropAction: DroviaAction {
    let id = "actions.airdrop"
    let wheel = WheelKind.actions
    let title = "AirDrop"
    let symbol: String? = "dot.radiowaves.left.and.right"
    /// Shows the AirDrop sheet.
    let needsUser = true

    func supports(_ types: [UTType]) -> Bool {
        !types.isEmpty
    }

    func perform(_ files: [URL], context _: ActionContext) async throws -> ActionResult {
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: files) else {
            throw ActionError(String(localized: "AirDrop isn't available"))
        }
        NSApp.activate()
        service.perform(withItems: files)
        return .silent
    }
}

enum TerminalApp: String, CaseIterable, Identifiable {
    case terminal = "com.apple.Terminal"
    case iTerm = "com.googlecode.iterm2"
    case ghostty = "com.mitchellh.ghostty"
    case warp = "dev.warp.Warp-Stable"

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .terminal: "Terminal"
        case .iTerm: "iTerm2"
        case .ghostty: "Ghostty"
        case .warp: "Warp"
        }
    }

    var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue)
    }

    static var installed: [TerminalApp] {
        allCases.filter { $0.appURL != nil }
    }
}

struct TerminalAction: DroviaAction {
    let id = "actions.terminal"
    let wheel = WheelKind.actions
    let symbol: String? = "apple.terminal"

    var title: String {
        String(localized: "Terminal")
    }

    func supports(_ types: [UTType]) -> Bool {
        !types.isEmpty
    }

    func perform(_ files: [URL], context: ActionContext) async throws -> ActionResult {
        let app = context.settings.terminalApp
        guard let appURL = app.appURL ?? TerminalApp.terminal.appURL else {
            throw ActionError(String(localized: "\(app.title) isn't installed"))
        }
        // A folder opens as is; a file opens its containing folder.
        let folders = files.map { $0.hasDirectoryPath ? $0 : $0.deletingLastPathComponent() }
        let unique = folders.reduce(into: [URL]()) {
            if !$0.contains($1) {
                $0.append($1)
            }
        }
        try await NSWorkspace.shared.open(unique, withApplicationAt: appURL, configuration: .init())
        return .silent
    }
}

struct RevealAction: DroviaAction {
    let id = "actions.reveal"
    let wheel = WheelKind.actions
    let symbol: String? = "magnifyingglass"

    var title: String {
        String(localized: "Reveal")
    }

    func supports(_ types: [UTType]) -> Bool {
        !types.isEmpty
    }

    func perform(_ files: [URL], context _: ActionContext) async throws -> ActionResult {
        NSWorkspace.shared.activateFileViewerSelecting(files)
        return .silent
    }
}

struct OpenWithAction: DroviaAction {
    let id = "actions.openwith"
    let wheel = WheelKind.actions
    let symbol: String? = "arrow.up.forward.app"
    /// Asks which app with a menu.
    let needsUser = true

    var title: String {
        String(localized: "Open With")
    }

    func supports(_ types: [UTType]) -> Bool {
        !types.isEmpty
    }

    func perform(_ files: [URL], context _: ActionContext) async throws -> ActionResult {
        guard let first = files.first else { return .silent }
        let workspace = NSWorkspace.shared
        let defaultApp = workspace.urlForApplication(toOpen: first)
        // Apps that can open every dropped file, the default one first.
        var apps = workspace.urlsForApplications(toOpen: first).filter { app in
            files.dropFirst().allSatisfy { workspace.urlsForApplications(toOpen: $0).contains(app) }
        }
        if let defaultApp, let index = apps.firstIndex(of: defaultApp) {
            apps.insert(apps.remove(at: index), at: 0)
        }
        func entry(_ app: URL) -> MenuPicker.Entry<URL> {
            .init(
                title: FileManager.default.displayName(atPath: app.path),
                image: MenuPicker.icon(forFile: app.path),
                value: app
            )
        }
        let sections = [Array(apps.prefix(1)).map(entry), apps.dropFirst().map(entry)]
        guard let app = MenuPicker.pick(sections, title: String(localized: "Open With")) else {
            throw CancellationError()
        }
        try await workspace.open(files, withApplicationAt: app, configuration: .init())
        return .silent
    }
}

struct ActionError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}
