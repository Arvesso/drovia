import AppKit
import UniformTypeIdentifiers

struct MoveAction: DroviaAction {
    let id = "actions.move"
    let wheel = WheelKind.actions
    let symbol: String? = "folder"

    var title: String {
        String(localized: "Move")
    }

    var progressTitle: String {
        String(localized: "Moving")
    }

    func supports(_ types: [UTType]) -> Bool {
        !types.isEmpty
    }

    func perform(_ files: [URL], context: ActionContext) async throws -> ActionResult {
        guard let folder = await chooseDestination(settings: context.settings) else { throw CancellationError() }
        context.settings.noteMoveDestination(folder.path)

        var result = ActionResult()
        for file in files {
            do {
                let fileName = NamingTemplate.uniqueFileName(
                    base: file.deletingPathExtension().lastPathComponent,
                    fileExtension: file.pathExtension
                ) { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
                let destination = folder.appendingPathComponent(fileName)
                try FileManager.default.moveItem(at: file, to: destination)
                result.processed.append(ProcessedFile(source: file, output: destination))
            } catch {
                result.failures.append(ActionFailure(file: file, message: error.localizedDescription))
            }
        }
        result.message = String(localized: "Moved \(result.outputs.count) files")
        result.detail = (folder.path as NSString).abbreviatingWithTildeInPath
        return result
    }

    private func chooseDestination(settings: SettingsStore) async -> URL? {
        enum Choice { case folder(String), browse }

        func entries(_ paths: [String]) -> [MenuPicker.Entry<Choice>] {
            paths.filter { FileManager.default.fileExists(atPath: $0) }.map {
                .init(
                    title: FileManager.default.displayName(atPath: $0),
                    image: MenuPicker.icon(forFile: $0),
                    value: .folder($0)
                )
            }
        }
        let recents = settings.recentMoveFolders.filter { !settings.favoriteFolders.contains($0) }
        let browse = MenuPicker.Entry<Choice>(
            title: String(localized: "Choose Folder…"),
            image: NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: nil),
            value: .browse
        )
        let choice = MenuPicker.pick(
            [entries(settings.favoriteFolders), entries(recents), [browse]],
            title: String(localized: "Move to")
        )
        switch choice {
        case let .folder(path):
            return URL(fileURLWithPath: path, isDirectory: true)
        case .browse:
            return await FolderPanel.choose(prompt: String(localized: "Move Here"))
        case nil:
            return nil
        }
    }
}

@MainActor
enum FolderPanel {
    static func choose(prompt: String, message: String? = nil) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = prompt
        panel.message = message ?? ""
        NSApp.activate()
        return await panel.begin() == .OK ? panel.url : nil
    }
}
