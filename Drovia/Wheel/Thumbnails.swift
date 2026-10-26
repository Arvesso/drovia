import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

enum Thumbnails {
    /// A preview of the first dragged item: a Quick Look thumbnail when possible, otherwise its icon.
    @MainActor
    static func image(for content: DragContent, side: CGFloat = 68) async -> NSImage {
        if let url = content.fileURLs.first {
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            if let cgImage = await quickLookThumbnail(for: url, side: side, scale: scale) {
                return NSImage(cgImage: cgImage, size: .zero)
            }
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        let type = content.promisedTypes.first ?? (content.hasImageData ? .png : .data)
        return NSWorkspace.shared.icon(for: type)
    }

    private static func quickLookThumbnail(for url: URL, side: CGFloat, scale: CGFloat) async -> CGImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: side, height: side),
            scale: scale,
            representationTypes: .thumbnail
        )
        // A drag that ends early cancels its request, so quick drags of large videos don't pile up work.
        nonisolated(unsafe) let pending = request
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                    continuation.resume(returning: representation?.cgImage)
                }
            }
        } onCancel: {
            QLThumbnailGenerator.shared.cancel(pending)
        }
    }
}
