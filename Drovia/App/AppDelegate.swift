import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let folderAccess = FolderAccess()
    private lazy var wheelCoordinator = WheelCoordinator(folderAccess: folderAccess)

    func applicationDidFinishLaunching(_: Notification) {
        wheelCoordinator.start()
    }
}
