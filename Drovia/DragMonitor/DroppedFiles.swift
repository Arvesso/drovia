import AppKit
import os

/// Files dropped onto Drovia. Captured synchronously during the drop, because the drag pasteboard
/// is only valid until the drop finishes, then resolved to real file URLs asynchronously.
@MainActor
struct DroppedFiles {
    private var fileURLs: [URL] = []
    private var receivers: [NSFilePromiseReceiver] = []
    private var imageData: Data?

    init(pasteboard: NSPasteboard) {
        fileURLs = pasteboard.fileURLs
        guard fileURLs.isEmpty else { return }
        receivers = pasteboard.promiseReceivers
        guard receivers.isEmpty else { return }
        imageData = pasteboard.data(forType: .png)
            ?? pasteboard.data(forType: .tiff).flatMap { NSBitmapImageRep(data: $0)?.representation(
                using: .png,
                properties: [:]
            ) }
    }

    /// File URLs ready to process. Promised files and raw images are written to a temporary folder.
    func resolve() async throws -> [URL] {
        if !fileURLs.isEmpty {
            return fileURLs
        }
        if receivers.isEmpty, imageData == nil {
            return []
        }

        let folder = try Self.makeTemporaryFolder()
        if let imageData {
            let url = folder.appendingPathComponent("Dragged Image.png")
            try imageData.write(to: url)
            return [url]
        }

        var urls: [URL] = []
        for receiver in receivers {
            try await urls.append(Self.receive(receiver, into: folder))
        }
        return urls
    }

    private static let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }()

    private static func receive(_ receiver: NSFilePromiseReceiver, into folder: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            receiver.receivePromisedFiles(
                atDestination: folder,
                options: [:],
                operationQueue: promiseQueue,
                reader: firstFileReader(resuming: continuation)
            )
        }
    }

    /// Built outside the main actor because the reader is called on `promiseQueue`.
    /// One receiver may call back once per promised file; we take the first.
    private nonisolated static func firstFileReader(
        resuming continuation: CheckedContinuation<URL, any Error>
    ) -> @Sendable (URL, (any Error)?) -> Void {
        let resumed = OSAllocatedUnfairLock(initialState: false)
        return { url, error in
            guard resumed.withLock({ let was = $0; $0 = true; return !was }) else { return }
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(returning: url)
            }
        }
    }

    /// Where promised files and raw images are written; results for them go to Downloads instead.
    nonisolated static let temporaryRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("Dropped", isDirectory: true)

    /// Files received from Safari, Mail and the like in an earlier session. Nothing refers to them any more
    /// (results went to Downloads), and they may be large or private attachments.
    nonisolated static func removeLeftovers() {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    private static func makeTemporaryFolder() throws -> URL {
        let folder = temporaryRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
