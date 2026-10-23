import SwiftUI

struct SettingsView: View {
    @Environment(FolderAccess.self) private var folderAccess
    @State private var selection = SettingsTab.general

    var body: some View {
        TabView(selection: $selection) {
            Tab("General", systemImage: "gearshape", value: .general) {
                GeneralSettingsView()
            }
            Tab("Folders", systemImage: "folder", value: .folders) {
                FoldersSettingsView()
            }
        }
        .frame(width: 520, height: 440)
        .onAppear {
            // Until something is allowed, folders are the only setting that matters.
            if folderAccess.folders.isEmpty {
                selection = .folders
            }
        }
    }
}

private enum SettingsTab: Hashable {
    case general
    case folders
}

private struct GeneralSettingsView: View {
    var body: some View {
        Form {
            LabeledContent("Version", value: Bundle.main.appVersion)
        }
        .formStyle(.grouped)
    }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
