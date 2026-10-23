import AppKit
import UniformTypeIdentifiers

/// What is being dragged, read from the drag pasteboard when a file drag starts.
struct DragContent: Equatable, Sendable {
    var fileURLs: [URL] = []
    /// Types of files promised by apps like Safari or Mail, which are only written on drop.
    var promisedTypes: [UTType] = []
    /// Raw image data without a file (e.g. dragged from some editors).
    var hasImageData = false
    var itemCount = 0

    var isEmpty: Bool {
        itemCount == 0
    }

    @MainActor
    static var acceptedTypes: [NSPasteboard.PasteboardType] {
        [.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
            + [.png, .tiff]
    }

    @MainActor
    init(pasteboard: NSPasteboard) {
        fileURLs = pasteboard.fileURLs
        if !fileURLs.isEmpty {
            itemCount = fileURLs.count
            return
        }
        let receivers = pasteboard.promiseReceivers
        if !receivers.isEmpty {
            promisedTypes = receivers.flatMap { $0.fileTypes.compactMap(UTType.init) }
            itemCount = receivers.count
            return
        }
        if pasteboard.canReadObject(forClasses: [NSImage.self], options: nil) {
            hasImageData = true
            itemCount = 1
        }
    }

    init() {}
}

extension NSPasteboard {
    var fileURLs: [URL] {
        readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    var promiseReceivers: [NSFilePromiseReceiver] {
        readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver] ?? []
    }
}
