import AppKit
import PDFKit
import UniformTypeIdentifiers

enum PDFEngineError: LocalizedError {
    case unreadable(URL)
    case locked(URL)
    case cannotWrite(URL)

    var errorDescription: String? {
        switch self {
        case let .unreadable(url): String(localized: "Can't open \(url.lastPathComponent) as a PDF")
        case let .locked(url): String(localized: "\(url.lastPathComponent) is password-protected")
        case let .cannotWrite(url): String(localized: "Can't write \(url.lastPathComponent)")
        }
    }
}

/// PDF processing on top of PDFKit. Each call opens its own document, so calls can run in parallel.
enum PDFEngine {
    static func open(_ url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url) else { throw PDFEngineError.unreadable(url) }
        guard !document.isLocked else { throw PDFEngineError.locked(url) }
        return document
    }

    static func pageCount(of url: URL) throws -> Int {
        try open(url).pageCount
    }

    /// Renders one page at `scale` × its point size (2 = 144 dpi), white background, rotation applied.
    static func renderPage(_ index: Int, of url: URL, scale: CGFloat = 2) throws -> CGImage {
        let document = try open(url)
        guard let page = document.page(at: index) else { throw PDFEngineError.unreadable(url) }
        let bounds = page.bounds(for: .cropBox)
        let rotated = page.rotation % 180 != 0
        let size = CGSize(
            width: (rotated ? bounds.height : bounds.width) * scale,
            height: (rotated ? bounds.width : bounds.height) * scale
        )
        guard let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw PDFEngineError.unreadable(url)
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .cropBox, to: context)
        return try context.makeImage().orThrow(PDFEngineError.unreadable(url))
    }

    /// Combines PDFs and images, in order, into one PDF.
    static func merge(_ urls: [URL], to destination: URL) throws {
        let merged = PDFDocument()
        for url in urls {
            if UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true {
                let document = try open(url)
                for index in 0 ..< document.pageCount {
                    if let page = document.page(at: index)?.copy() as? PDFPage {
                        merged.insert(page, at: merged.pageCount)
                    }
                }
            } else {
                guard let image = NSImage(contentsOf: url), let page = PDFPage(image: image) else {
                    throw PDFEngineError.unreadable(url)
                }
                merged.insert(page, at: merged.pageCount)
            }
        }
        try write(merged, to: destination)
    }

    /// Writes each page as its own PDF into `folder`, named `<name>-01.pdf`, `<name>-02.pdf`…
    static func split(_ url: URL, into folder: URL) throws -> Int {
        let document = try open(url)
        let name = url.deletingPathExtension().lastPathComponent
        for index in 0 ..< document.pageCount {
            guard let page = document.page(at: index)?.copy() as? PDFPage else { continue }
            let single = PDFDocument()
            single.insert(page, at: 0)
            try write(
                single,
                to: folder.appendingPathComponent(pageFileName(name, index, of: document.pageCount, ext: "pdf"))
            )
        }
        return document.pageCount
    }

    /// Re-saves with images recompressed as JPEG and downsampled for screens.
    static func compress(_ url: URL, to destination: URL) throws {
        let document = try open(url)
        guard document.write(to: destination, withOptions: [
            .saveImagesAsJPEGOption: true,
            .optimizeImagesForScreenOption: true,
        ]) else {
            throw PDFEngineError.cannotWrite(destination)
        }
    }

    static func rotateClockwise(_ url: URL, to destination: URL) throws {
        let document = try open(url)
        for index in 0 ..< document.pageCount {
            document.page(at: index)?.rotation += 90
        }
        try write(document, to: destination)
    }

    /// Clears title, author, creator and the other document attributes.
    static func removeMetadata(_ url: URL, to destination: URL) throws {
        let document = try open(url)
        document.documentAttributes = [:]
        try write(document, to: destination)
    }

    static func text(of url: URL) throws -> String {
        try open(url).string ?? ""
    }

    static func pageFileName(_ name: String, _ index: Int, of count: Int, ext: String) -> String {
        let digits = max(2, String(count).count)
        let number = String(index + 1)
        return "\(name)-\(String(repeating: "0", count: max(0, digits - number.count)))\(number).\(ext)"
    }

    private static func write(_ document: PDFDocument, to destination: URL) throws {
        guard document.write(to: destination) else { throw PDFEngineError.cannotWrite(destination) }
    }
}
