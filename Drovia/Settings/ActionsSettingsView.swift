import SwiftUI

struct ActionsSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Terminal", selection: $settings.terminalApp) {
                    ForEach(TerminalApp.installed) { Text($0.title).tag($0) }
                }
                Picker("Copy Path as", selection: $settings.copyPathFormat) {
                    ForEach(CopyPathFormat.allCases) { Text($0.title).tag($0) }
                }
            }

            Section {
                ForEach(settings.favoriteFolders, id: \.self) { path in
                    HStack {
                        Image(nsImage: MenuPicker.icon(forFile: path))
                        Text((path as NSString).abbreviatingWithTildeInPath)
                            .truncationMode(.middle)
                            .lineLimit(1)
                        Spacer()
                        Button("Remove", systemImage: "minus.circle.fill") {
                            settings.favoriteFolders.removeAll { $0 == path }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                }
                Button("Add Folder…", systemImage: "plus") {
                    Task {
                        if let url = await FolderPanel.choose(prompt: String(localized: "Add")),
                           !settings.favoriteFolders.contains(url.path)
                        {
                            settings.favoriteFolders.append(url.path)
                        }
                    }
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Move Destinations")
            } footer: {
                Text("Shown first when you drop files on Move, followed by recent folders.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
