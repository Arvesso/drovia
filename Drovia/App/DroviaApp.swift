import SwiftUI

@main
struct DroviaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Drovia", systemImage: "circle.dashed.inset.filled") {
            MenuBarContent(folderAccess: appDelegate.folderAccess)
        }

        Settings {
            SettingsView()
                .environment(appDelegate.folderAccess)
                .environment(appDelegate.settings)
        }
    }
}
