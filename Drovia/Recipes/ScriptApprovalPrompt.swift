import AppKit

/// Asks before running a recipe script Drovia hasn't seen: shows the script, and Cancel is the default.
@MainActor
enum ScriptApprovalPrompt {
    static func ask(toRun script: String, in recipe: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Run the script in “\(recipe)”?")
        alert.informativeText = String(localized: """
        Drovia didn't see this script being written, so another app may have changed it. It would run with \
        Drovia's access to your folders.
        """)
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.addButton(withTitle: String(localized: "Run"))

        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 160))
        text.string = script
        text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        text.isEditable = false
        text.textContainerInset = NSSize(width: 4, height: 4)
        let scroll = NSScrollView(frame: text.frame)
        scroll.documentView = text
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        alert.accessoryView = scroll

        NSApp.activate()
        return alert.runModal() == .alertSecondButtonReturn
    }
}
