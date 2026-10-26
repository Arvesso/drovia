import SwiftUI

struct MenuBarContent: View {
    let folderAccess: FolderAccess
    let onboarding: OnboardingController
    let history: HistoryStore
    let shelf: ShelfController
    let runner: ActionRunner

    var body: some View {
        if !folderAccess.hasAccess {
            Text("No folders allowed yet")
            OpenSettingsButton("Choose Folders…")
            Divider()
        }

        if let last = history.lastUndoable {
            Button("Undo \(last.title)") { runner.undo(last) }
        }
        Button(shelf.model.items.isEmpty
            ? LocalizedStringKey("Show Shelf")
            : "Show Shelf (\(shelf.model.items.count))")
        {
            shelf.show()
        }

        if !history.entries.isEmpty {
            Divider()
            Section("Recent") {
                ForEach(history.entries.prefix(8)) { entry in
                    Menu {
                        if !entry.outputs.isEmpty {
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting(entry.outputs)
                            }
                        }
                        Button("Undo") { runner.undo(entry) }
                            .disabled(!entry.canUndo)
                    } label: {
                        Label(entry.title, systemImage: entry.isUndone ? "arrow.uturn.backward" : entry.symbol)
                        Text(entry.date, style: .time)
                    }
                }
                Button("Clear History") { history.clear() }
            }
        }

        Divider()

        Button("Welcome Guide…") { onboarding.show() }
        OpenSettingsButton("Settings…")
            .keyboardShortcut(",")

        Button("Quit Drovia") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

/// Opens Settings in front of other apps. `SettingsLink` doesn't activate a menu bar app,
/// so its window would open behind whatever app is active.
struct OpenSettingsButton: View {
    @Environment(\.openSettings) private var openSettings
    private let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Button(title) {
            NSApp.activate()
            openSettings()
            // The window may be created on the next run loop turn; bring it forward once it exists.
            Task { @MainActor in
                NSApp.windows.first { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }?
                    .makeKeyAndOrderFront(nil)
            }
        }
    }
}
