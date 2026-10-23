import KeyboardShortcuts
import SwiftUI

/// The global shortcut that opens the wheel for Finder's selection, and Finder access for it.
struct KeyboardSection: View {
    @State private var finderStatus = FinderAutomation.Status.undetermined

    var body: some View {
        Section {
            KeyboardShortcuts.Recorder("Open wheel for Finder selection", name: .showWheel)

            LabeledContent("Finder access") {
                HStack {
                    switch finderStatus {
                    case .allowed:
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .denied:
                        Label("Denied", systemImage: "xmark.circle.fill").foregroundStyle(.orange)
                        Button("Open Privacy Settings") { NSWorkspace.shared.open(FinderAutomation.settingsURL) }
                    case .undetermined, .finderNotRunning:
                        Button("Allow…") { requestAccess() }
                    }
                }
            }
        } header: {
            Text("Keyboard")
        } footer: {
            Text(
                "Select files in Finder and press the shortcut: the wheel opens at the pointer. Tab switches wheels, arrows or number keys choose an action."
            )
            .foregroundStyle(.secondary)
        }
        .task { await refresh(ask: false) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refresh(ask: false) }
        }
    }

    private func requestAccess() {
        NSApp.activate()
        Task { await refresh(ask: true) }
    }

    /// The check can block on macOS's consent prompt, so it runs off the main thread.
    private func refresh(ask: Bool) async {
        finderStatus = await Task.detached { FinderAutomation.status(ask: ask) }.value
    }
}
