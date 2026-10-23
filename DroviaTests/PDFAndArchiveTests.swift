import AppKit
@testable import Drovia
import PDFKit
import Testing
import UniformTypeIdentifiers

struct PDFEngineTests {
    private let folder: TemporaryFolder

    init() throws {
        folder = try TemporaryFolder()
    }

    /// A PDF with `pages` A5 pages, each with a black square in the top-left corner.
    private func makePDF(_ name: String, pages: Int) throws -> URL {
        let url = folder.url.appendingPathComponent(name)
        var box = CGRect(x: 0, y: 0, width: 420, height: 595)
        let context = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
        for _ in 0 ..< pages {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 495, width: 100, height: 100))
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    @Test func rendersPageAtDoubleScale() throws {
        let pdf = try makePDF("a.pdf", pages: 1)
        let image = try PDFEngine.renderPage(0, of: pdf)
        #expect(image.width == 840 && image.height == 1190)
    }

    @Test func rendersRotatedPageWithSwappedSize() throws {
        let pdf = try makePDF("a.pdf", pages: 1)
        let rotated = folder.url.appendingPathComponent("rotated.pdf")
        try PDFEngine.rotateClockwise(pdf, to: rotated)
        let image = try PDFEngine.renderPage(0, of: rotated)
        #expect(image.width == 1190 && image.height == 840)
    }

    @Test func mergesPDFsAndImages() throws {
        let first = try makePDF("a.pdf", pages: 2)
        let second = try makePDF("b.pdf", pages: 1)
        let image = folder.url.appendingPathComponent("c.png")
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 10, pixelsHigh: 10, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        try rep.representation(using: .png, properties: [:])?.write(to: image)

        let merged = folder.url.appendingPathComponent("merged.pdf")
        try PDFEngine.merge([first, second, image], to: merged)
        #expect(try PDFEngine.pageCount(of: merged) == 4)
    }

    @Test func splitsIntoNumberedPages() throws {
        let pdf = try makePDF("doc.pdf", pages: 3)
        let output = folder.url.appendingPathComponent("pages")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        #expect(try PDFEngine.split(pdf, into: output) == 3)
        let names = try FileManager.default.contentsOfDirectory(atPath: output.path).sorted()
        #expect(names == ["doc-01.pdf", "doc-02.pdf", "doc-03.pdf"])
    }

    @Test func pageFileNamesArePadded() {
        #expect(PDFEngine.pageFileName("doc", 0, of: 5, ext: "png") == "doc-01.png")
        #expect(PDFEngine.pageFileName("doc", 9, of: 120, ext: "png") == "doc-010.png")
    }
}

struct ArchiveEngineTests {
    private let folder: TemporaryFolder

    init() throws {
        folder = try TemporaryFolder()
    }

    private func makeFile(_ name: String, in directory: URL? = nil) throws -> URL {
        let url = (directory ?? folder.url).appendingPathComponent(name)
        try Data(name.utf8).write(to: url)
        return url
    }

    @Test func zipsAndExtractsSeveralFiles() async throws {
        let a = try makeFile("a.txt")
        let b = try makeFile("b.txt")
        let zip = folder.url.appendingPathComponent("Archive.zip")
        try await ArchiveEngine.zip([a, b], to: zip)

        let target = folder.url.appendingPathComponent("Archive")
        let extracted = try await ArchiveEngine.extract(zip, into: target)
        #expect(extracted == target)
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.path).sorted() == ["a.txt", "b.txt"])
    }

    @Test func singleItemArchiveExtractsWithoutExtraFolder() async throws {
        let source = folder.url.appendingPathComponent("Photos")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        _ = try makeFile("one.txt", in: source)
        let zip = folder.url.appendingPathComponent("Photos.zip")
        try await ArchiveEngine.zip([source], to: zip)
        try FileManager.default.removeItem(at: source)

        let extracted = try await ArchiveEngine.extract(zip, into: folder.url.appendingPathComponent("Photos"))
        #expect(extracted.lastPathComponent == "Photos")
        #expect(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("one.txt").path))
    }

    @Test func sha256MatchesKnownValue() throws {
        let file = folder.url.appendingPathComponent("abc.txt")
        try Data("abc".utf8).write(to: file)
        #expect(try ArchiveEngine.sha256(of: file)
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

@MainActor
struct DocumentEngineTests {
    private let folder: TemporaryFolder

    init() throws {
        folder = try TemporaryFolder()
    }

    @Test func convertsRichTextToEveryFormat() throws {
        let source = folder.url.appendingPathComponent("note.rtf")
        let text = NSAttributedString(string: "Hello, Drovia", attributes: [.font: NSFont.boldSystemFont(ofSize: 20)])
        try text.data(
            from: NSRange(location: 0, length: text.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        .write(to: source)

        for format in DocumentFormat.allCases {
            let output = folder.url.appendingPathComponent("note.\(format.fileExtension)")
            try DocumentEngine.write(DocumentEngine.read(source), as: format, to: output)
            #expect((output.fileSize ?? 0) > 0, "\(format)")
        }
        let pdf = try #require(PDFDocument(url: folder.url.appendingPathComponent("note.pdf")))
        #expect(pdf.string?.contains("Hello, Drovia") == true)
    }
}

@MainActor
struct ActionRegistryTests {
    private func titles(_ wheel: WheelKind, _ extensions: [String]) -> [String] {
        ActionRegistry.actions(for: wheel, types: extensions.map { UTType(filenameExtension: $0)! }).map(\.id)
    }

    @Test func convertOffersOtherImageFormats() {
        let ids = titles(.convert, ["png"])
        #expect(!ids.contains("convert.png"))
        #expect(ids.contains("convert.webp") && ids.contains("convert.pdf"))
    }

    @Test func pdfGetsPDFTools() {
        #expect(titles(.convert, ["pdf"]) == [
            "convert.pdf.png",
            "convert.pdf.jpeg",
            "convert.pdf.tiff",
            "convert.pdf.text",
        ])
        #expect(titles(.tools, ["pdf"]) == [
            "tools.compress.pdf",
            "tools.text",
            "tools.split",
            "tools.rotate.pdf",
            "tools.metadata.pdf",
        ])
        #expect(titles(.tools, ["pdf", "jpg"]) == ["tools.text", "tools.merge"])
    }

    @Test func imagesGetEditorAndSmartTools() {
        #expect(titles(.tools, ["png"]) == [
            "tools.compress", "tools.resize", "tools.crop", "tools.annotate", "tools.addbg", "tools.removebg",
            "tools.redact", "tools.text", "tools.rotate", "tools.metadata",
        ])
    }

    @Test func documentsConvertToOtherDocumentFormats() {
        #expect(titles(.convert, ["docx"]) == [
            "convert.doc.pdf",
            "convert.doc.rtf",
            "convert.doc.html",
            "convert.doc.txt",
        ])
    }

    @Test func archivesGetUnzipInsteadOfZip() {
        #expect(titles(.actions, ["zip"]).contains("actions.unzip"))
        #expect(!titles(.actions, ["zip"]).contains("actions.zip"))
        #expect(titles(.actions, ["txt"]).contains("actions.zip"))
    }

    @Test func videosAndAudioGetMediaActions() {
        #expect(titles(.convert, ["mp4"]) == [
            "convert.video.mov",
            "convert.video.gif",
            "convert.audio.m4a",
            "convert.audio.wav",
            "convert.audio.aiff",
        ])
        #expect(titles(.tools, ["mov"]) == ["tools.compress.video", "tools.mute.video", "tools.rotate.video"])
        #expect(titles(.convert, ["mp3"]) == ["convert.audio.m4a", "convert.audio.wav", "convert.audio.aiff"])
    }

    @Test func otherFilesGetChecksum() {
        #expect(titles(.tools, ["dmg"]) == ["tools.checksum"])
        #expect(titles(.convert, ["dmg"]).isEmpty)
    }
}
