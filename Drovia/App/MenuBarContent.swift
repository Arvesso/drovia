import SwiftUI

struct MenuBarContent: View {
    var body: some View {
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
