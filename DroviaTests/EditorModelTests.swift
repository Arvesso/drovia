import AppKit
@testable import Drovia
import Testing

@MainActor
struct EditorModelTests {
    private let folder: TemporaryFolder
    private let model: EditorModel

    /// Opens the editor on a 400×200 PNG.
    init() throws {
        folder = try TemporaryFolder()
        let url = folder.url.appendingPathComponent("image.png")
        try ImageEngine.encode(
            TestImages.solid(RGBA(0x336699), width: 400, height: 200),
            properties: [:],
            as: .png,
            to: url,
            quality: 1
        )
        model = EditorModel(files: [url], mode: .crop, redaction: .blackBox)
    }

    @Test func startsWithFullImageCrop() {
        #expect(model.imageSize == CGSize(width: 400, height: 200))
        #expect(model.crop == CGRect(x: 0, y: 0, width: 400, height: 200))
    }

    @Test func dragsNewCropClampedToImage() {
        model.dragCrop(.new, from: model.crop, start: CGPoint(x: 350, y: 150), to: CGPoint(x: 500, y: 300))
        #expect(model.crop == CGRect(x: 350, y: 150, width: 50, height: 50))
    }

    @Test func cornerDragKeepsOppositeCorner() {
        let initial = model.crop
        model.dragCrop(.topLeft, from: initial, start: .zero, to: CGPoint(x: 100, y: 50))
        #expect(model.crop == CGRect(x: 100, y: 50, width: 300, height: 150))
    }

    @Test func aspectRatioIsApplied() {
        model.cropAspect = .square
        #expect(model.crop.width == model.crop.height)
        model.dragCrop(.new, from: model.crop, start: CGPoint(x: 10, y: 10), to: CGPoint(x: 210, y: 60))
        #expect(model.crop.width == model.crop.height)
    }

    @Test func moveStaysInsideImage() {
        model.dragCrop(.new, from: model.crop, start: .zero, to: CGPoint(x: 100, y: 100))
        model.dragCrop(.move, from: model.crop, start: CGPoint(x: 50, y: 50), to: CGPoint(x: 1000, y: 1000))
        #expect(model.crop == CGRect(x: 300, y: 100, width: 100, height: 100))
    }

    @Test func annotationsUndoAndRedo() {
        model.tool = .rectangle
        model.beginAnnotation(at: CGPoint(x: 10, y: 10))
        model.updateAnnotation(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 100, y: 80))
        model.endAnnotation(at: CGPoint(x: 100, y: 80))
        #expect(model.annotations.count == 1)
        model.undo()
        #expect(model.annotations.isEmpty)
        model.redo()
        #expect(model.annotations.count == 1)
    }

    @Test func clicksDontLeaveAnnotations() {
        model.tool = .arrow
        model.beginAnnotation(at: CGPoint(x: 10, y: 10))
        model.endAnnotation(at: CGPoint(x: 10, y: 10))
        #expect(model.annotations.isEmpty)
        #expect(!model.canUndo)
    }

    @Test func textToolCollectsTypedText() {
        model.tool = .text
        model.beginAnnotation(at: CGPoint(x: 20, y: 20))
        model.endAnnotation(at: CGPoint(x: 20, y: 20))
        model.textEntry?.text = "Hello"
        model.commitText()
        #expect(model.annotations.count == 1)
        #expect(model.textEntry == nil)
    }

    @Test func savingReturnsRenderedImage() async {
        var results: [EditedImage] = []
        model.onFinish = { results = $0 }
        model.mode = .background
        await model.save()
        #expect(results.count == 1)
        // The default background adds padding around the 400×200 image.
        #expect((results.first?.image.width ?? 0) > 400)
    }
}
