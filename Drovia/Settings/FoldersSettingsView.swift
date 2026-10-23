import SwiftUI

struct FoldersSettingsView: View {
    @Environment(FolderAccess.self) private var folderAccess

    var body: some View {
        Form {
            Section {
                if folderAccess.folders.isEmpty {
                    EmptyFoldersView()
                } else {
                    ForEach(folderAccess.folders) { folder in
                        FolderRow(folder: folder)
                    }
                    Button("Add Folder…", systemImage: "plus") {
                        folderAccess.chooseFolders()
                    }
                    .buttonStyle(.borderless)
                }
            } header: {
                Text("Allowed Folders")
            } footer: {
                Text(
                    "Drovia only reacts to files inside these folders, including all their subfolders. macOS may ask once for Desktop, Documents and Downloads when you add a folder containing them."
                )
                .foregroundStyle(.secondary)
            }

            Section {
                FullDiskAccessRow()
            } header: {
                Text("Full Disk Access")
            } footer: {
                Text(
                    "Optional. One switch instead of separate prompts, and it also covers external and network drives."
                )
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            folderAccess.refreshFullDiskAccess()
        }
    }
}

private struct EmptyFoldersView: View {
    @Environment(FolderAccess.self) private var folderAccess

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
            Text("Choose where Drovia works")
                .font(.headline)
            Text("Adding your Home folder covers everything inside it.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button("Add Home Folder") {
                    folderAccess.addHomeFolder()
                }
                .buttonStyle(.borderedProminent)
                Button("Choose Folders…") {
                    folderAccess.chooseFolders()
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

private struct FolderRow: View {
    @Environment(FolderAccess.self) private var folderAccess
    let folder: AllowedFolder

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: folder.isHome ? "house.fill" : "folder.fill")
                .foregroundStyle(.tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(folder.displayName)
                Text(folder.abbreviatedPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .truncationMode(.middle)
            }
            .lineLimit(1)
            Spacer()
            Button("Remove", systemImage: "minus.circle.fill") {
                folderAccess.remove(folder)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Remove")
        }
    }
}

private struct FullDiskAccessRow: View {
    @Environment(FolderAccess.self) private var folderAccess

    private static let settingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    var body: some View {
        HStack {
            if folderAccess.hasFullDiskAccess {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Not granted", systemImage: "circle.dashed")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Privacy Settings") {
                NSWorkspace.shared.open(Self.settingsURL)
            }
        }
    }
}
