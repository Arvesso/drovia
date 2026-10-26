import Foundation
import UniformTypeIdentifiers

enum RecipeError: LocalizedError {
    case stepDoesNotFit(String)
    case emptyRecipe

    var errorDescription: String? {
        switch self {
        case let .stepDoesNotFit(step): String(localized: "“\(step)” can't handle these files")
        case .emptyRecipe: String(localized: "This recipe has no steps")
        }
    }
}

/// Runs a recipe's steps in order, feeding each step the files the previous one produced.
/// Intermediate files live in temporary folders; only the last file-producing step writes where results go.
struct RecipeAction: DroviaAction {
    let recipe: Recipe
    let wheel = WheelKind.recipes

    var id: String {
        "recipe.\(recipe.id.uuidString)"
    }

    var title: String {
        recipe.name
    }

    var symbol: String? {
        recipe.symbol
    }

    var progressTitle: String {
        recipe.name
    }

    var producesFiles: Bool {
        stepActions.contains { $0?.producesFiles == true }
    }

    var isInteractive: Bool {
        stepActions.contains { $0?.isInteractive == true }
    }

    /// The first variant of each action step, to know what the step does in general.
    private var stepActions: [(any DroviaAction)?] {
        recipe.steps.map { step in
            guard case let .action(sectorID) = step else { return nil }
            return ActionRegistry.all.first { $0.sectorID == sectorID }
        }
    }

    /// Whether every action step finds a variant for the files as they'll be at that point.
    func supports(_ types: [UTType]) -> Bool {
        guard !recipe.steps.isEmpty, !types.isEmpty else { return false }
        var types = types
        for step in recipe.steps {
            guard case let .action(sectorID) = step else { continue }
            guard ActionRegistry.all.contains(where: { $0.sectorID == sectorID && $0.supports(types) })
            else { return false }
            // A conversion changes the type of what follows.
            if sectorID.hasPrefix("convert."), let type = UTType(filenameExtension: String(sectorID.dropFirst(8))) {
                types = Array(repeating: type, count: types.count)
            }
        }
        return true
    }

    func perform(_ files: [URL], context: ActionContext) async throws -> ActionResult {
        guard !recipe.steps.isEmpty else { throw RecipeError.emptyRecipe }
        let lastProducing = stepActions.lastIndex { $0?.producesFiles == true }
        let slug = recipe.name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: "-")

        // The same file passed twice (possible from Shortcuts) is processed once.
        var seen: Set<URL> = []
        var current = files.filter { seen.insert($0).inserted }
        // Each current file mapped to the original it came from.
        var origin = Dictionary(uniqueKeysWithValues: current.map { ($0, $0) })
        var temporaryFolders: [URL] = []
        defer { temporaryFolders.forEach { try? FileManager.default.removeItem(at: $0) } }
        var result = ActionResult()

        // The final files are named after the recipe: photo-for-the-web.webp.
        func finalPlanner() -> OutputPlanner {
            OutputPlanner(
                location: context.planner.location,
                template: context.planner.template.replacingOccurrences(of: "{action}", with: slug),
                originals: origin.filter { $0.key != $0.value }
            )
        }

        steps: for (index, step) in recipe.steps.enumerated() {
            let stepProgress: (Double) -> Void = { fraction in
                context.reportProgress((Double(index) + fraction) / Double(recipe.steps.count))
            }
            switch step {
            case .shortcut, .script:
                try await RecipeScripts.run(step, on: current)
                continue
            case let .action(sectorID):
                let types = current.map { UTType(filenameExtension: $0.pathExtension) ?? .data }
                guard let action = ActionRegistry.all.first(where: { $0.sectorID == sectorID && $0.supports(types) })
                else {
                    throw RecipeError.stepDoesNotFit(step.title)
                }

                let planner: OutputPlanner
                if action.producesFiles, index != lastProducing {
                    let folder = FileManager.default.temporaryDirectory
                        .appendingPathComponent("Recipe-\(UUID().uuidString)", isDirectory: true)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    temporaryFolders.append(folder)
                    planner = OutputPlanner(location: .folder(folder), template: "{name}")
                } else {
                    planner = finalPlanner()
                }
                let stepContext = ActionContext(
                    settings: context.settings,
                    planner: planner,
                    shelf: context.shelf,
                    reportProgress: stepProgress
                )
                let stepResult = try await action.perform(current, context: stepContext)
                result.failures += stepResult.failures
                result.undo += stepResult.undo
                result.message = stepResult.message ?? result.message
                result.detail = stepResult.detail ?? result.detail

                // Files a step left alone (already small enough) go on unchanged; failed ones drop out.
                if action.producesFiles || !stepResult.outputs.isEmpty {
                    var next: [URL] = []
                    for processed in stepResult.processed {
                        let file = processed.output ?? processed.source
                        // Several sources can share one result (a zip); it goes on once.
                        guard !next.contains(file) else { continue }
                        origin[file] = origin[processed.source] ?? processed.source
                        next.append(file)
                    }
                    current = next
                }
                if current.isEmpty {
                    break steps
                }
            }
        }

        // A last step that left files alone (already small enough) hands back intermediate files.
        // Move them to where results go before their temporary folders are deleted.
        let intermediate = current.filter { file in
            temporaryFolders.contains { file.path.hasPrefix($0.path + "/") }
        }
        if !intermediate.isEmpty {
            let planner = finalPlanner()
            for file in intermediate {
                let destination = await planner.destination(for: file, action: slug, fileExtension: file.pathExtension)
                try FileManager.default.moveItem(at: file, to: destination)
                origin[destination] = origin[file]
                current = current.map { $0 == file ? destination : $0 }
            }
        }

        // Report files that are new results, against the originals they came from.
        if lastProducing != nil {
            result.processed = current.compactMap { file in
                guard let original = origin[file], original != file else { return nil }
                return ProcessedFile(source: original, output: file)
            }
        }
        if !result.outputs.isEmpty {
            result.message = nil
        }
        return result
    }
}
