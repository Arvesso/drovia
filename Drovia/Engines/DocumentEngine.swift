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

/// Text documents via NSAttributedString. Main thread only: HTML import uses WebKit.
@MainActor
enum DocumentEngine {
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

    static func write(_ text: NSAttributedString, as format: DocumentFormat, to url: URL) throws {
        let range = NSRange(location: 0, length: text.length)
        switch format {
        case .pdf:
            try writePDF(text, to: url)
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

    /// Lays the text out on A4/Letter pages (per the system default) and prints to a PDF file.
    private static func writePDF(_ text: NSAttributedString, to url: URL) throws {
        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        printInfo.topMargin = 56
        printInfo.bottomMargin = 56
        printInfo.leftMargin = 56
        printInfo.rightMargin = 56
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isVerticallyCentered = false

        let width = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        // Print in light mode even if the system is dark, or unstyled text would come out white.
        textView.appearance = NSAppearance(named: .aqua)
        textView.textStorage?.setAttributedString(text)
        textView.isVerticallyResizable = true
        if let container = textView.textContainer, let layout = textView.layoutManager {
            layout.ensureLayout(for: container)
            textView.frame.size.height = layout.usedRect(for: container).height + 1
        }

        let operation = NSPrintOperation(view: textView, printInfo: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else { throw PDFEngineError.cannotWrite(url) }
    }
}
