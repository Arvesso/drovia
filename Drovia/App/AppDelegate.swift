import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let folderAccess = FolderAccess()
    let settings = SettingsStore()
    let history = HistoryStore()
    let shelf = ShelfController()
    private let toast = ToastPresenter()
    private(set) lazy var runner = ActionRunner(settings: settings, toast: toast, history: history, shelf: shelf)
    private lazy var wheelCoordinator = WheelCoordinator(
        folderAccess: folderAccess, settings: settings, runner: runner, toast: toast
    )

    func applicationDidFinishLaunching(_: Notification) {
        wheelCoordinator.start()
        // Files dragged out of the shelf can go onto the wheel too.
        shelf.onDragStart = { [weak self] in self?.wheelCoordinator.beginInternalDrag(with: $0) }
        shelf.onDragEnd = { [weak self] in self?.wheelCoordinator.endInternalDrag() }
    }
}
