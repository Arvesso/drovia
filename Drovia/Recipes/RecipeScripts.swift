import Foundation

/// Runs the Shortcuts and shell-script steps of recipes.
enum RecipeScripts {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    static func run(_ step: Recipe.Step, on files: [URL]) async throws {
        switch step {
        case let .shortcut(name):
            try await execute("/usr/bin/shortcuts", ["run", name] + files.flatMap { ["--input-path", $0.path] })
        case let .script(source):
            // "$@" holds the files; the script runs in the first file's folder.
            try await execute(
                "/bin/zsh",
                ["-c", source, "drovia"] + files.map(\.path),
                directory: files.first?.deletingLastPathComponent()
            )
        case .action:
            break
        }
    }

    /// Names of the user's shortcuts, for the recipe editor.
    static func shortcutNames() async -> [String] {
        await (try? execute("/usr/bin/shortcuts", ["list"]))?
            .split(separator: "\n").map(String.init).filter { !$0.isEmpty }.sorted() ?? []
    }

    @discardableResult
    private static func execute(_ tool: String, _ arguments: [String], directory: URL? = nil) async throws -> String {
        let result = try await Subprocess.run(tool, arguments, directory: directory)
        guard result.status == 0 else {
            throw Failure(errorDescription: result.errorMessage
                ?? "\((tool as NSString).lastPathComponent) exited with \(result.status)")
        }
        return String(decoding: result.standardOutput, as: UTF8.self)
    }
}
