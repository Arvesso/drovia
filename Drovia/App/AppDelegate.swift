import AppKit
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// For App Intents, which run inside the app but outside the SwiftUI scene.
    private(set) weak static var current: AppDelegate?

    let folderAccess = FolderAccess()
    let settings = SettingsStore()
    let history = HistoryStore()
    let shelf = ShelfController()
    private let toast = ToastPresenter()
    private(set) lazy var runner = ActionRunner(settings: settings, toast: toast, history: history, shelf: shelf)
    private lazy var wheelCoordinator = WheelCoordinator(
        folderAccess: folderAccess, settings: settings, runner: runner, toast: toast
    )

    override init() {
        super.init()
        Self.current = self
    }

    func applicationDidFinishLaunching(_: Notification) {
        wheelCoordinator.start()
        // Files dragged out of the shelf can go onto the wheel too.
        shelf.onDragStart = { [weak self] in self?.wheelCoordinator.beginInternalDrag(with: $0) }
        shelf.onDragEnd = { [weak self] in self?.wheelCoordinator.endInternalDrag() }
        KeyboardShortcuts.onKeyUp(for: .showWheel) { [weak self] in self?.wheelCoordinator.openForFinderSelection() }
    }
}
