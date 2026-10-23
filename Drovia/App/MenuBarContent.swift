import SwiftUI

struct MenuBarContent: View {
    let folderAccess: FolderAccess
    let history: HistoryStore
    let shelf: ShelfController
    let runner: ActionRunner

    var body: some View {
        if folderAccess.folders.isEmpty {
            Text("No folders allowed yet")
            SettingsLink {
                Text("Choose Folders…")
            }
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

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")

        Button("Quit Drovia") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
