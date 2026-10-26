import AppKit
import UniformTypeIdentifiers

enum DocumentFormat: String, CaseIterable, Sendable {
    case pdf, docx, rtf, html, txt

    var title: String {
        rawValue.uppercased()
    }

    var fileExtension: String {
        rawValue
    }

    var utType: UTType {
        switch self {
        case .pdf: .pdf
        case .docx: UTType("org.openxmlformats.wordprocessingml.document") ?? .data
        case .rtf: .rtf
        case .html: .html
        case .txt: .plainText
        }
    }

    /// Types we can read as styled text.
    static let readableTypes: [UTType] = [
        .rtf, .rtfd, .html, .plainText,
        UTType("org.openxmlformats.wordprocessingml.document"),
        UTType("com.microsoft.word.doc"),
        UTType("org.oasis-open.opendocument.text"),
    ].compactMap(\.self)

    static func isReadable(_ type: UTType) -> Bool {
        readableTypes.contains { type.conforms(to: $0) }
    }
}

/// Text documents via NSAttributedString. Reading HTML uses WebKit and must happen on the main thread;
/// everything else can run anywhere, so long documents don't freeze the app.
enum DocumentEngine {
    /// A4, for when the system's default paper isn't known.
    static let a4 = CGSize(width: 595, height: 842)
    private static let margin: CGFloat = 56

    static func needsMainThread(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .html) == true
    }

    /// Reads `source` and writes it as `format`. Call on the main thread when `needsMainThread(source)`.
    static func convert(_ source: URL, to format: DocumentFormat, at destination: URL, paperSize: CGSize = a4) throws {
        try write(read(source), as: format, to: destination, paperSize: paperSize)
    }

    static func read(_ url: URL) throws -> NSAttributedString {
        var text = try NSAttributedString(url: url, options: [:], documentAttributes: nil)
        // Plain text has no fonts; give it a readable default.
        if UTType(filenameExtension: url.pathExtension)?.conforms(to: .plainText) == true {
            let styled = NSMutableAttributedString(string: text.string, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            ])
            text = styled
        }
        return text
    }

    static func write(
        _ text: NSAttributedString,
        as format: DocumentFormat,
        to url: URL,
        paperSize: CGSize = a4
    ) throws {
        let range = NSRange(location: 0, length: text.length)
        switch format {
        case .pdf:
            try writePDF(text, to: url, paperSize: paperSize)
        case .txt:
            try text.string.write(to: url, atomically: true, encoding: .utf8)
        case .docx:
            try text.data(
                from: range,
                documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
            )
            .write(to: url, options: .atomic)
        case .rtf:
            try text.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
                .write(to: url, options: .atomic)
        case .html:
            try text.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.html])
                .write(to: url, options: .atomic)
        }
    }

    /// Lays the text out page by page with TextKit and draws it into a PDF. A layout manager that isn't
    /// attached to a view may be used on any thread, unlike printing an NSTextView.
    private static func writePDF(_ text: NSAttributedString, to url: URL, paperSize: CGSize) throws {
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let textSize = CGSize(width: paperSize.width - margin * 2, height: paperSize.height - margin * 2)
        var pages: [NSTextContainer] = []
        repeat {
            let container = NSTextContainer(size: textSize)
            layout.addTextContainer(container)
            pages.append(container)
            let glyphs = layout.glyphRange(for: container)
            // Done when the text ends, or when nothing fits on a page (an image taller than a page).
            if NSMaxRange(glyphs) >= layout.numberOfGlyphs || glyphs.length == 0 {
                break
            }
        } while true

        var mediaBox = CGRect(origin: .zero, size: paperSize)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw PDFEngineError.cannotWrite(url)
        }
        let graphics = NSGraphicsContext(cgContext: context, flipped: true)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = graphics
        defer { NSGraphicsContext.current = previous }
        // Light appearance even if the system is dark, or text without a color would come out white.
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            for container in pages {
                context.beginPDFPage(nil)
                context.saveGState()
                // TextKit draws top-down.
                context.translateBy(x: 0, y: paperSize.height)
                context.scaleBy(x: 1, y: -1)
                let glyphs = layout.glyphRange(for: container)
                let origin = CGPoint(x: margin, y: margin)
                layout.drawBackground(forGlyphRange: glyphs, at: origin)
                layout.drawGlyphs(forGlyphRange: glyphs, at: origin)
                context.restoreGState()
                context.endPDFPage()
            }
        }
        context.closePDF()
    }
}
