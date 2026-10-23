import AppKit

/// Pops up a menu at the cursor and returns the chosen item's value.
@MainActor
enum MenuPicker {
    struct Entry<Value> {
        var title: String
        var image: NSImage?
        var value: Value
    }

    /// Sections are separated by dividers. Returns `nil` if the menu is dismissed.
    static func pick<Value>(_ sections: [[Entry<Value>]], title: String? = nil) -> Value? {
        let menu = NSMenu()
        menu.autoenablesItems = false
        if let title {
            menu.addItem(.sectionHeader(title: title))
        }
        var chosen: Value?
        for (index, section) in sections.enumerated() where !section.isEmpty {
            if index > 0, !menu.items.isEmpty {
                menu.addItem(.separator())
            }
            for entry in section {
                let item = ClosureMenuItem(title: entry.title) { chosen = entry.value }
                item.image = entry.image
                menu.addItem(item)
            }
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        return chosen
    }

    static func icon(forFile path: String) -> NSImage {
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func run() {
        handler()
    }
}
