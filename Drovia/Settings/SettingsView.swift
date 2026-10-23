import SwiftUI

struct SettingsView: View {
    @Environment(FolderAccess.self) private var folderAccess
    @State private var selection = SettingsTab.general

    var body: some View {
        TabView(selection: $selection) {
            Tab("General", systemImage: "gearshape", value: .general) {
                GeneralSettingsView()
            }
            Tab("Files", systemImage: "doc.on.doc", value: .files) {
                FilesSettingsView()
            }
            Tab("Actions", systemImage: "bolt", value: .actions) {
                ActionsSettingsView()
            }
            Tab("Folders", systemImage: "folder", value: .folders) {
                FoldersSettingsView()
            }
        }
        .frame(width: 540, height: 500)
        .onAppear {
            // Until something is allowed, folders are the only setting that matters.
            if folderAccess.folders.isEmpty {
                selection = .folders
            }
        }
    }
}

private enum SettingsTab: Hashable {
    case general, files, actions, folders
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
