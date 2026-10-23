import AppKit
import UniformTypeIdentifiers

struct CopyAction: DroviaAction {
    let id = "actions.copy"
    let wheel = WheelKind.actions
    let symbol: String? = "doc.on.doc"

    var title: String {
        String(localized: "Copy")
    }

    func supports(_ types: [UTType]) -> Bool {
        !types.isEmpty
    }

    func perform(_ files: [URL], context _: ActionContext) async throws -> ActionResult {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(files as [NSURL])
        return ActionResult(
            message: String(localized: "Copied \(files.count) files"),
            detail: String(localized: "Paste them in Finder")
        )
    }
}

enum CopyPathFormat: String, CaseIterable, Identifiable, Sendable {
    case posix, tilde, quoted, markdown, fileURL

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .posix: String(localized: "Full path")
        case .tilde: String(localized: "Path with ~")
        case .quoted: String(localized: "Shell-quoted path")
        case .markdown: String(localized: "Markdown link")
        case .fileURL: String(localized: "File URL")
        }
    }

    func format(_ url: URL, home: String = NSHomeDirectory()) -> String {
        let path = url.path
        switch self {
        case .posix:
            return path
        case .tilde:
            return path == home || path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
        case .quoted:
            return "'" + path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
        case .markdown:
            let name = url.lastPathComponent.replacingOccurrences(of: "]", with: #"\]"#)
            return "[\(name)](\(url.absoluteString))"
        case .fileURL:
            return url.absoluteString
        }
    }
}

struct CopyPathAction: DroviaAction {
    let id = "actions.copypath"
    let wheel = WheelKind.actions
    let symbol: String? = "doc.text"

    var title: String {
        String(localized: "Copy Path")
    }

    func supports(_ types: [UTType]) -> Bool {
        !types.isEmpty
    }

    func perform(_ files: [URL], context: ActionContext) async throws -> ActionResult {
        let format = context.settings.copyPathFormat
        let text = files.map { format.format($0) }.joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return ActionResult(
            message: String(localized: "Copied \(files.count) paths"),
            detail: files.count == 1 ? text : format.title
        )
    }
}
