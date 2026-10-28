@testable import Drovia
import Foundation
import Testing

struct NamingTemplateTests {
    private let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 12))!

    @Test func rendersTokens() {
        #expect(NamingTemplate.render("{name}-{action}", name: "photo", action: "compressed") == "photo-compressed")
        #expect(NamingTemplate.render("{date} {name}", name: "photo", action: "x", date: date) == "2026-10-23 photo")
    }

    @Test func replacesPathSeparators() {
        #expect(NamingTemplate.render("{name}/{action}:x", name: "a", action: "b") == "a-b-x")
    }

    @Test func emptyOrHiddenResultFallsBackToName() {
        #expect(NamingTemplate.render("  ", name: "photo", action: "x") == "photo")
        #expect(NamingTemplate.render(".{action}", name: "photo", action: "x") == "photo")
    }

    @Test func uniqueNamesFollowFinderStyle() {
        let taken: Set = ["a.png", "a 2.png"]
        #expect(NamingTemplate.uniqueFileName(base: "b", fileExtension: "png") { taken.contains($0) } == "b.png")
        #expect(NamingTemplate.uniqueFileName(base: "a", fileExtension: "png") { taken.contains($0) } == "a 3.png")
        #expect(NamingTemplate.uniqueFileName(base: "dir", fileExtension: "") { _ in false } == "dir")
    }
}

struct OutputPlannerTests {
    @Test func reservesNamesForParallelJobs() async throws {
        let folder = try TemporaryFolder()
        let planner = OutputPlanner(location: .nextToOriginal, template: "{name}-{action}")
        let a = folder.url.appendingPathComponent("photo.png")
        let b = folder.url.appendingPathComponent("photo.jpg")
        let first = await planner.destination(for: a, action: nil, fileExtension: "webp")
        let second = await planner.destination(for: b, action: nil, fileExtension: "webp")
        #expect(first.lastPathComponent == "photo.webp")
        #expect(second.lastPathComponent == "photo 2.webp")
    }

    @Test func usesTemplateForToolsAndCustomFolder() async throws {
        let folder = try TemporaryFolder()
        let planner = OutputPlanner(location: .folder(folder.url), template: "{name}-{action}")
        let result = await planner.destination(
            for: URL(fileURLWithPath: "/elsewhere/photo.jpg"), action: "compressed", fileExtension: "jpg"
        )
        #expect(result == folder.url.appendingPathComponent("photo-compressed.jpg"))
    }
}

struct CopyPathFormatTests {
    private let url = URL(fileURLWithPath: "/Users/me/My 'Docs'/a.txt")

    @Test func formats() {
        #expect(CopyPathFormat.posix.format(url) == "/Users/me/My 'Docs'/a.txt")
        #expect(CopyPathFormat.tilde.format(url, home: "/Users/me") == "~/My 'Docs'/a.txt")
        #expect(CopyPathFormat.tilde.format(url, home: "/Users/m") == "/Users/me/My 'Docs'/a.txt")
        #expect(CopyPathFormat.quoted.format(url) == #"'/Users/me/My '\''Docs'\''/a.txt'"#)
        #expect(CopyPathFormat.fileURL.format(url) == "file:///Users/me/My%20'Docs'/a.txt")
        #expect(CopyPathFormat.markdown.format(url) == "[a.txt](file:///Users/me/My%20'Docs'/a.txt)")
    }
}

struct ResizePresetTests {
    @Test func neverUpscales() {
        #expect(ResizePreset.side1600.targetSide(for: 4000) == 1600)
        #expect(ResizePreset.side1600.targetSide(for: 800) == 800)
        #expect(ResizePreset.half.targetSide(for: 801) == 400)
    }
}

/// A fresh temporary folder, removed when the value is deinitialized.
final class TemporaryFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("DroviaTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

/// UserDefaults of its own for a test, kept in memory. A suite on disk leaves a plist in
/// ~/Library/Preferences per test run: cfprefsd writes it again a minute later even after the domain is
/// removed and the file deleted.
final class TestDefaults {
    let defaults: UserDefaults = InMemoryDefaults()
}

private final class InMemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]

    init() {
        // A suite name is required to make a separate instance; nothing is ever read from or written to it.
        super.init(suiteName: "DroviaTests.InMemory")!
    }

    override func object(forKey key: String) -> Any? {
        values[key]
    }

    override func set(_ value: Any?, forKey key: String) {
        values[key] = value
    }

    override func removeObject(forKey key: String) {
        values[key] = nil
    }

    override func set(_ value: Bool, forKey key: String) {
        values[key] = value
    }

    override func set(_ value: Int, forKey key: String) {
        values[key] = value
    }

    override func set(_ value: Double, forKey key: String) {
        values[key] = value
    }

    override func string(forKey key: String) -> String? {
        values[key] as? String
    }

    override func stringArray(forKey key: String) -> [String]? {
        values[key] as? [String]
    }

    override func data(forKey key: String) -> Data? {
        values[key] as? Data
    }

    override func bool(forKey key: String) -> Bool {
        values[key] as? Bool ?? false
    }

    override func integer(forKey key: String) -> Int {
        values[key] as? Int ?? 0
    }

    override func double(forKey key: String) -> Double {
        values[key] as? Double ?? 0
    }
}
