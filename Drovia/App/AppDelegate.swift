import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let folderAccess = FolderAccess()
    let settings = SettingsStore()
    private lazy var wheelCoordinator = WheelCoordinator(folderAccess: folderAccess, settings: settings)

    func applicationDidFinishLaunching(_: Notification) {
        wheelCoordinator.start()
    }
}
