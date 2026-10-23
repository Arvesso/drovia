@testable import Drovia
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@MainActor
struct RecipeTests {
    private let folder: TemporaryFolder
    private let settings: SettingsStore

    init() throws {
        folder = try TemporaryFolder()
        settings = SettingsStore(defaults: UserDefaults(suiteName: "RecipeTests-\(UUID().uuidString)")!)
        settings.resizePreset = .half
    }

    private func context(_ planner: OutputPlanner? = nil) -> ActionContext {
        ActionContext(
            settings: settings,
            planner: planner ?? OutputPlanner(location: .nextToOriginal, template: "{name}-{action}"),
            shelf: ShelfController(),
            reportProgress: { _ in }
        )
    }

    private func png(_ name: String = "photo.png") throws -> URL {
        let url = folder.url.appendingPathComponent(name)
        try ImageEngine.encode(
            TestImages.solid(RGBA(0x3366AA), width: 400, height: 200),
            properties: [:],
            as: .png,
            to: url,
            quality: 1
        )
        return url
    }

    @Test func chainsStepsAndNamesResultAfterRecipe() async throws {
        let source = try png()
        let recipe = Recipe(name: "For the Web", symbol: "globe", steps: [
            .action(sectorID: "tools.resize"), .action(sectorID: "convert.webp"), .action(sectorID: "tools.metadata"),
        ])
        let result = try await RecipeAction(recipe: recipe).perform([source], context: context())
        #expect(result.failures.isEmpty)
        let output = try #require(result.outputs.first)
        // Next to the original, not in a temporary folder.
        #expect(output.deletingLastPathComponent().standardizedFileURL == folder.url.standardizedFileURL)
        #expect(output.lastPathComponent == "photo-for-the-web.webp")
        #expect(result.processed.first?.source == source)
        #expect(try ImageEngine.pixelSize(of: output) == CGSize(width: 200, height: 100))
    }

    @Test func supportsFollowsTypeChanges() {
        let recipe = Recipe(
            name: "x",
            symbol: "star",
            steps: [.action(sectorID: "convert.webp"), .action(sectorID: "tools.resize")]
        )
        let action = RecipeAction(recipe: recipe)
        #expect(action.supports([.png]))
        #expect(!action.supports([.mpeg4Movie]))
        #expect(!RecipeAction(recipe: Recipe(name: "empty", symbol: "star", steps: [])).supports([.png]))
    }

    @Test func scriptStepReceivesFiles() async throws {
        let source = try png()
        let marker = folder.url.appendingPathComponent("seen.txt")
        let recipe = Recipe(name: "Script", symbol: "terminal", steps: [
            .script("for f in \"$@\"; do basename \"$f\" >> '\(marker.path)'; done"),
        ])
        let result = try await RecipeAction(recipe: recipe).perform([source], context: context())
        #expect(result.outputs.isEmpty)
        #expect(try String(contentsOf: marker, encoding: .utf8) == "photo.png\n")
    }

    @Test func failingScriptStopsRecipe() async throws {
        let recipe = Recipe(name: "Broken", symbol: "terminal", steps: [.script("echo nope >&2; exit 3")])
        await #expect(throws: RecipeScripts.Failure.self) {
            _ = try await RecipeAction(recipe: recipe).perform([png()], context: context())
        }
    }

    @Test func recipesAppearOnOptionWheel() {
        let recipes = Recipe.examples
        let onPNG = ActionRegistry.actions(for: .recipes, types: [.png], recipes: recipes)
        #expect(onPNG.map(\.title) == recipes.map(\.name))
        #expect(ActionRegistry.action(id: onPNG[0].id, recipes: recipes) != nil)
    }
}
