import AppKit
import SwiftUI

/// Apps whose drags Drovia ignores, e.g. design tools that use modifier-drags themselves.
struct ExcludedAppsSection: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Section {
            ForEach(settings.excludedApps, id: \.self) { bundleID in
                HStack {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                        Image(nsImage: MenuPicker.icon(forFile: url.path))
                        Text(FileManager.default.displayName(atPath: url.path))
                    } else {
                        Image(systemName: "app.dashed")
                        Text(bundleID)
                    }
                    Spacer()
                    Button("Remove", systemImage: "minus.circle.fill") {
                        settings.excludedApps.removeAll { $0 == bundleID }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
            Button("Add App…", systemImage: "plus") { chooseApps() }
                .buttonStyle(.borderless)
        } header: {
            Text("Ignore Drags From")
        } footer: {
            Text("Useful for apps where you hold modifier keys while dragging, like design tools or games.")
                .foregroundStyle(.secondary)
        }
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate()
        panel.begin { response in
            guard response == .OK else { return }
            MainActor.assumeIsolated {
                let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
                settings.excludedApps += ids.filter { !settings.excludedApps.contains($0) }
            }
        }
    }
}
