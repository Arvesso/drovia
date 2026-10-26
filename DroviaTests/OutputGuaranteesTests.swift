@testable import Drovia
import Foundation
import Testing

/// "Results never clobber existing files" and "every change can be undone".
@MainActor
struct OutputGuaranteesTests {
    private let folder: TemporaryFolder

    init() throws {
        folder = try TemporaryFolder()
    }

    private func makeFile(_ name: String) throws -> URL {
        let url = folder.url.appendingPathComponent(name)
        try Data(name.utf8).write(to: url)
        return url
    }

    @Test func plannerTreatsNamesDifferingOnlyInCaseAsTheSame() async throws {
        let planner = OutputPlanner(location: .nextToOriginal, template: "{name}")
        let first = try await planner.destination(for: makeFile("Photo.png"), action: nil, fileExtension: "webp")
        let second = try await planner.destination(for: makeFile("photo.jpg"), action: nil, fileExtension: "webp")
        #expect(first.lastPathComponent.lowercased() != second.lastPathComponent.lowercased())
    }

    @Test func zipReportsEveryFileItContains() async throws {
        let files = try ["a.txt", "b.txt", "c.txt"].map(makeFile)
        let testDefaults = TestDefaults()
        let settings = SettingsStore(defaults: testDefaults.defaults)
        let context = ActionContext(
            settings: settings,
            planner: OutputPlanner(location: .nextToOriginal, template: "{name}-{action}"),
            shelf: ShelfController(),
            reportProgress: { _ in }
        )
        let result = try await ZipAction().perform(files, context: context)
        #expect(result.processed.map(\.source) == files)
        #expect(result.outputs.count == 1)
    }

    @Test func unreadableRecipeDoesNotLoseTheOthers() throws {
        let testDefaults = TestDefaults()
        let defaults = testDefaults.defaults
        let kept = Recipe(name: "Kept", symbol: "star", steps: [.action(sectorID: "tools.resize")])
        var stored = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode([kept])) as? [Any])
        // A step kind from a newer version.
        stored.append(["id": UUID().uuidString, "name": "Future", "symbol": "star", "steps": [["teleport": [:]]]])
        try defaults.set(JSONSerialization.data(withJSONObject: stored), forKey: "recipes")
        #expect(SettingsStore(defaults: defaults).recipes.map(\.name) == ["Kept"])
    }

    @Test func wheelLayoutWithMissingFieldsKeepsTheRest() throws {
        let layout = try JSONDecoder().decode(WheelLayout.self, from: Data(#"{"order":{"tools":["a","b"]}}"#.utf8))
        #expect(layout.order["tools"] == ["a", "b"])
        #expect(layout.hidden.isEmpty)
    }
}
