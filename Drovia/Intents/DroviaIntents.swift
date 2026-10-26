import AppIntents
import Foundation
import UniformTypeIdentifiers

// MARK: - Entities

/// A wheel sector (Compress, WebP, Remove BG…) offered as a choice in Shortcuts.
struct DroviaActionEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Drovia Action")
    static let defaultQuery = DroviaActionQuery()

    let id: String
    let title: String
    let wheel: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(wheel)")
    }
}

struct DroviaActionQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [DroviaActionEntity] {
        await all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [DroviaActionEntity] {
        await all()
    }

    /// Sectors that run unattended only: Shortcuts can't wait for an editor window or a menu.
    @MainActor
    private func all() -> [DroviaActionEntity] {
        WheelKind.allCases.filter { $0 != .recipes }.flatMap { wheel in
            ActionRegistry.sectors(for: wheel, layout: WheelLayout())
                .filter { sector in !ActionRegistry.all.contains { $0.sectorID == sector.id && $0.needsUser } }
                .map { DroviaActionEntity(id: $0.id, title: $0.title, wheel: wheel.title) }
        }
    }
}

struct RecipeEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Drovia Recipe")
    static let defaultQuery = RecipeQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct RecipeQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [RecipeEntity] {
        await recipes().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [RecipeEntity] {
        await recipes()
    }

    @MainActor
    private func recipes() -> [RecipeEntity] {
        (AppDelegate.current?.settings.recipes ?? SettingsStore().recipes)
            .map { RecipeEntity(id: $0.id, name: $0.name) }
    }
}

// MARK: - Intents

enum DroviaIntentError: LocalizedError {
    case unavailable
    case unsupported(String)
    case failed(String)
    case needsUser(String)
    case notAllowed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: String(localized: "Drovia isn't ready yet. Try again.")
        case let .unsupported(action): String(localized: "“\(action)” can't handle these files")
        case let .failed(message): message
        case let .needsUser(recipe):
            String(localized: "“\(recipe)” opens the editor or asks something, so it can't run from Shortcuts")
        case let .notAllowed(file):
            String(
                localized: "\(file) isn't in a folder Drovia is allowed to use. Add it in Drovia Settings → Folders."
            )
        }
    }
}

struct ProcessFilesIntent: AppIntent {
    static let title: LocalizedStringResource = "Process Files with Drovia"
    static let description =
        IntentDescription("Runs a Drovia action, like Compress or Convert to WebP, and returns the new files.")

    @Parameter(title: "Files", supportedContentTypes: [.item])
    var files: [IntentFile]

    @Parameter(title: "Action")
    var action: DroviaActionEntity

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$action) \(\.$files)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        guard let app = AppDelegate.current else { throw DroviaIntentError.unavailable }
        let urls = try IntentFiles.urls(for: files, allowedBy: app.folderAccess)
        let types = urls.map(FileType.of)
        guard let droviaAction = ActionRegistry.all.first(where: { $0.sectorID == action.id && $0.supports(types) })
        else {
            throw DroviaIntentError.unsupported(action.title)
        }
        return try await .result(value: IntentFiles.run(droviaAction, on: urls, with: app))
    }
}

struct RunRecipeIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Drovia Recipe"
    static let description = IntentDescription("Runs one of your Drovia recipes and returns the new files.")

    @Parameter(title: "Files", supportedContentTypes: [.item])
    var files: [IntentFile]

    @Parameter(title: "Recipe")
    var recipe: RecipeEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$recipe) on \(\.$files)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        guard let app = AppDelegate.current else { throw DroviaIntentError.unavailable }
        guard let stored = app.settings.recipes.first(where: { $0.id == recipe.id }) else {
            throw DroviaIntentError.unsupported(recipe.name)
        }
        let action = RecipeAction(recipe: stored)
        // A step that opens the editor or a menu would wait for someone who isn't there.
        guard !action.needsUser else { throw DroviaIntentError.needsUser(stored.name) }
        let urls = try IntentFiles.urls(for: files, allowedBy: app.folderAccess)
        guard action.supports(urls.map(FileType.of)) else {
            throw DroviaIntentError.unsupported(stored.name)
        }
        return try await .result(value: IntentFiles.run(action, on: urls, with: app))
    }
}

@MainActor
private enum IntentFiles {
    /// Files from Shortcuts may come as data only; those are written to a temporary folder. Real files
    /// must be in an allowed folder, as for drags: Drovia only touches files in folders the user allowed.
    static func urls(for files: [IntentFile], allowedBy access: FolderAccess) throws -> [URL] {
        try files.map { file in
            if let url = file.fileURL {
                guard access.allows(DragContent(fileURLs: [url])) else {
                    throw DroviaIntentError.notAllowed(url.lastPathComponent)
                }
                return url
            }
            let folder = DroppedFiles.temporaryRoot.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // The name comes from the shortcut: keep it from reaching outside the folder.
            let name = (file.filename as NSString).lastPathComponent
            let url = folder.appendingPathComponent(name.isEmpty || name == ".." ? "File" : name)
            try file.data.write(to: url)
            return url
        }
    }

    /// Data-only inputs were copied for the run; the results went elsewhere (Downloads).
    static func removeTemporaryCopies(of urls: [URL]) {
        for url in urls where url.path.hasPrefix(DroppedFiles.temporaryRoot.path + "/") {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
    }

    static func run(_ action: any DroviaAction, on urls: [URL], with app: AppDelegate) async throws -> [IntentFile] {
        // Copies of data-only inputs are only needed while the files are made; actions that don't make
        // files may hand the copy on (to the shelf, the clipboard), so theirs stay until next launch.
        defer {
            if action.producesFiles {
                removeTemporaryCopies(of: urls)
            }
        }
        let (result, _) = try await app.runner.execute(action, on: urls, allowsPrompts: false)
        if result.outputs.isEmpty, let failure = result.failures.first {
            throw DroviaIntentError.failed(failure.message)
        }
        return result.outputs.map { IntentFile(fileURL: $0, filename: $0.lastPathComponent) }
    }
}
