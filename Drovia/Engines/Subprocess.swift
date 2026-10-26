import Foundation

/// Runs command-line tools.
enum Subprocess {
    struct Output: Sendable {
        let status: Int32
        let standardOutput: Data
        let standardError: Data

        /// The tool's stderr, if it said anything.
        var errorMessage: String? {
            let message = String(decoding: standardError, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return message.isEmpty ? nil : message
        }
    }

    /// Runs `tool` to completion. Both pipes are drained while it runs: a tool that fills a pipe
    /// (about 64 KB) would otherwise block forever. Cancelling the calling task terminates the tool.
    static func run(
        _ tool: String,
        _ arguments: [String],
        directory: URL? = nil,
        environment: [String: String]? = nil
    ) async throws -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        if let directory {
            process.currentDirectoryURL = directory
        }
        if let environment {
            process.environment = environment
        }
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        async let standardOutput = readToEnd(output)
        async let standardError = readToEnd(errors)
        let status: Int32
        do {
            status = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            } onCancel: {
                if process.isRunning {
                    process.terminate()
                }
            }
        } catch {
            // The tool never started, so nothing closes the write ends the readers are waiting on.
            try? output.fileHandleForWriting.close()
            try? errors.fileHandleForWriting.close()
            _ = await (standardOutput, standardError)
            throw error
        }
        return await Output(status: status, standardOutput: standardOutput, standardError: standardError)
    }

    /// Reads on a plain thread: the read blocks until the tool closes the pipe.
    private static func readToEnd(_ pipe: Pipe) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: pipe.fileHandleForReading.readDataToEndOfFile())
            }
        }
    }
}
