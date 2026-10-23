import SwiftUI

struct MenuBarContent: View {
    let folderAccess: FolderAccess

    var body: some View {
        if folderAccess.folders.isEmpty {
            Text("No folders allowed yet")
            SettingsLink {
                Text("Choose Folders…")
            }
            Divider()
        }

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit Drovia") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
