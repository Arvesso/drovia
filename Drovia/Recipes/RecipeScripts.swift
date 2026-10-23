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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        if let directory {
            process.currentDirectoryURL = directory
        }
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                guard process.terminationStatus == 0 else {
                    let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: Failure(errorDescription: message?.isEmpty == false
                            ? message :
                            "\((tool as NSString).lastPathComponent) exited with \(process.terminationStatus)"))
                    return
                }
                continuation.resume(returning: text)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
