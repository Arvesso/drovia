import SwiftUI

@main
struct DroviaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Drovia", systemImage: "circle.dashed.inset.filled") {
            MenuBarContent(
                folderAccess: appDelegate.folderAccess,
                onboarding: appDelegate.onboarding,
                history: appDelegate.history,
                shelf: appDelegate.shelf,
                runner: appDelegate.runner
            )
        }

        Settings {
            SettingsView()
                .environment(appDelegate.folderAccess)
                .environment(appDelegate.settings)
        }
        // Drovia runs in the background: no window should come back on its own after a restart or login.
        .restorationBehavior(.disabled)
    }
}
