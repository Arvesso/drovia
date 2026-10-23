import AppKit
import Observation

enum EditorMode: String, CaseIterable, Identifiable {
    case crop, annotate, background

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .crop: String(localized: "Crop")
        case .annotate: String(localized: "Annotate")
        case .background: String(localized: "Background")
        }
    }

    var symbol: String {
        switch self {
        case .crop: "crop"
        case .annotate: "pencil.tip"
        case .background: "photo.on.rectangle"
        }
    }
}

enum CropAspect: String, CaseIterable, Identifiable {
    case free, original, square, standard, wide, photo, portrait

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .free: String(localized: "Free")
        case .original: String(localized: "Original")
        case .square: "1:1"
        case .standard: "4:3"
        case .wide: "16:9"
        case .photo: "3:2"
        case .portrait: "9:16"
        }
    }

    func ratio(for imageSize: CGSize) -> CGFloat? {
        switch self {
        case .free: nil
        case .original: imageSize.width / imageSize.height
        case .square: 1
        case .standard: 4 / 3
        case .wide: 16 / 9
        case .photo: 3 / 2
        case .portrait: 9 / 16
        }
    }
}

enum StrokeSize: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: Self {
        self
    }

    var lineWidth: CGFloat {
        switch self {
        case .small: 3
        case .medium: 6
        case .large: 11
        }
    }

    var fontSize: CGFloat {
        switch self {
        case .small: 24
        case .medium: 38
        case .large: 60
        }
    }
}

/// Which part of the crop rectangle a drag grabbed.
enum CropHandle {
    case topLeft, topRight, bottomLeft, bottomRight, move, new
}

struct EditedImage {
    let source: URL
    let image: CGImage
}

/// State of the image editor: one image at a time from a queue, with undo.
@MainActor
@Observable
final class EditorModel {
    struct Snapshot: Equatable, Hashable {
        var crop: CGRect
        var annotations: [Annotation]
        var background: BackgroundStyle
        var usesBackground: Bool
    }

    /// Longest side of the downscaled copy used for on-screen previews.
    private static let previewSide = 2048

    let files: [URL]
    private(set) var index = 0
    private(set) var imageSize = CGSize(width: 1, height: 1)
    /// Full-resolution pixels, used when saving.
    @ObservationIgnored private(set) var image: CGImage?
    /// Downscaled pixels for drawing on screen.
    private(set) var preview: CGImage?
    private(set) var loadError: String?

    var mode: EditorMode {
        didSet {
            if mode == .background {
                usesBackground = true
            }
        }
    }

    var crop = CGRect.zero
    var cropAspect = CropAspect.free {
        didSet { applyAspect() }
    }

    var annotations: [Annotation] = []
    var draft: Annotation?
    var tool = AnnotationTool.arrow
    var color = RGBA.palette[0]
    var strokeSize = StrokeSize.medium
    /// A text annotation being typed, at a point in image pixels.
    var textEntry: (point: CGPoint, text: String)?

    var background = BackgroundStyle()
    var usesBackground: Bool

    let redaction: RedactionStyle
    private(set) var isSaving = false

    @ObservationIgnored private var undoStack: [Snapshot] = []
    @ObservationIgnored private var redoStack: [Snapshot] = []
    @ObservationIgnored private var results: [EditedImage] = []
    @ObservationIgnored var onFinish: (([EditedImage]) -> Void)?

    init(files: [URL], mode: EditorMode, redaction: RedactionStyle) {
        self.files = files
        self.mode = mode
        self.redaction = redaction
        usesBackground = mode == .background
        load()
    }

    var source: URL {
        files[index]
    }

    var snapshot: Snapshot {
        Snapshot(crop: crop, annotations: annotations, background: background, usesBackground: usesBackground)
    }

    var canUndo: Bool {
        !undoStack.isEmpty
    }

    var canRedo: Bool {
        !redoStack.isEmpty
    }

    var hasMoreFiles: Bool {
        index + 1 < files.count
    }

    /// Scale of image pixels so strokes look alike on small and huge images.
    private var pixelScale: CGFloat {
        max(1, max(imageSize.width, imageSize.height) / 1400)
    }

    // MARK: - Undo

    /// Call before every user change.
    func recordUndo() {
        undoStack.append(snapshot)
        redoStack.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(snapshot)
        restore(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot)
        restore(next)
    }

    private func restore(_ snapshot: Snapshot) {
        crop = snapshot.crop
        annotations = snapshot.annotations
        background = snapshot.background
        usesBackground = snapshot.usesBackground
    }

    // MARK: - Crop

    func resetCrop() {
        recordUndo()
        cropAspect = .free
        crop = CGRect(origin: .zero, size: imageSize)
    }

    /// Updates the crop for a drag from `start` to `point` (image pixels), relative to the crop when the drag began.
    func dragCrop(_ handle: CropHandle, from initial: CGRect, start: CGPoint, to point: CGPoint) {
        let point = CGPoint(x: min(max(point.x, 0), imageSize.width), y: min(max(point.y, 0), imageSize.height))
        if handle == .move {
            var rect = initial.offsetBy(dx: point.x - start.x, dy: point.y - start.y)
            rect.origin.x = min(max(rect.minX, 0), imageSize.width - rect.width)
            rect.origin.y = min(max(rect.minY, 0), imageSize.height - rect.height)
            crop = rect
            return
        }
        // The fixed point: where a new crop started, or the corner opposite the grabbed one.
        let anchor: CGPoint = switch handle {
        case .topLeft: CGPoint(x: initial.maxX, y: initial.maxY)
        case .topRight: CGPoint(x: initial.minX, y: initial.maxY)
        case .bottomLeft: CGPoint(x: initial.maxX, y: initial.minY)
        case .bottomRight: CGPoint(x: initial.minX, y: initial.minY)
        case .new, .move: start
        }
        var size = CGSize(width: abs(point.x - anchor.x), height: abs(point.y - anchor.y))
        if let ratio = cropAspect.ratio(for: imageSize) {
            if size.width / max(size.height, 1) > ratio {
                size.width = size.height * ratio
            } else {
                size.height = size.width / ratio
            }
        }
        // Grow away from the anchor toward the pointer.
        let rect = CGRect(
            x: point.x < anchor.x ? anchor.x - size.width : anchor.x,
            y: point.y < anchor.y ? anchor.y - size.height : anchor.y,
            width: size.width, height: size.height
        ).intersection(CGRect(origin: .zero, size: imageSize))
        guard rect.width >= 16, rect.height >= 16 else { return }
        crop = rect
    }

    /// The largest crop with the chosen aspect, centered on the current one.
    private func applyAspect() {
        guard let ratio = cropAspect.ratio(for: imageSize) else { return }
        recordUndo()
        var size = CGSize(width: imageSize.width, height: imageSize.width / ratio)
        if size.height > imageSize.height {
            size = CGSize(width: imageSize.height * ratio, height: imageSize.height)
        }
        let center = CGPoint(x: crop.midX, y: crop.midY)
        var origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        origin.x = min(max(origin.x, 0), imageSize.width - size.width)
        origin.y = min(max(origin.y, 0), imageSize.height - size.height)
        crop = CGRect(origin: origin, size: size).integral
    }

    // MARK: - Annotations

    func beginAnnotation(at point: CGPoint) {
        let width = strokeSize.lineWidth * pixelScale
        let fontSize = strokeSize.fontSize * pixelScale
        let shape: Annotation.Shape = switch tool {
        case .arrow: .arrow(from: point, to: point)
        case .rectangle: .rectangle(CGRect(origin: point, size: .zero))
        case .ellipse: .ellipse(CGRect(origin: point, size: .zero))
        case .highlight: .highlight(CGRect(origin: point, size: .zero))
        case .pen: .pen([point])
        case .text: .text("", at: point)
        case .redact: .redact(CGRect(origin: point, size: .zero))
        }
        draft = Annotation(
            shape: shape,
            color: tool == .highlight ? RGBA(0xFFCC00) : color,
            lineWidth: width,
            fontSize: fontSize
        )
    }

    func updateAnnotation(from start: CGPoint, to point: CGPoint) {
        guard var draft else { return }
        let rect = CGRect(
            x: min(start.x, point.x),
            y: min(start.y, point.y),
            width: abs(point.x - start.x),
            height: abs(point.y - start.y)
        )
        switch draft.shape {
        case .arrow: draft.shape = .arrow(from: start, to: point)
        case .rectangle: draft.shape = .rectangle(rect)
        case .ellipse: draft.shape = .ellipse(rect)
        case .highlight: draft.shape = .highlight(rect)
        case let .pen(points): draft.shape = .pen(points + [point])
        case .redact: draft.shape = .redact(rect)
        case .text: break
        }
        self.draft = draft
    }

    func endAnnotation(at point: CGPoint) {
        defer { draft = nil }
        if tool == .text {
            textEntry = (point, "")
            return
        }
        guard let draft, !draft.isNegligible else { return }
        recordUndo()
        annotations.append(draft)
    }

    func commitText() {
        defer { textEntry = nil }
        guard let entry = textEntry else { return }
        let annotation = Annotation(
            shape: .text(entry.text, at: entry.point), color: color,
            lineWidth: strokeSize.lineWidth * pixelScale, fontSize: strokeSize.fontSize * pixelScale
        )
        guard !annotation.isNegligible else { return }
        recordUndo()
        annotations.append(annotation)
    }

    // MARK: - Background

    func setBackground(_ change: (inout BackgroundStyle) -> Void) {
        recordUndo()
        change(&background)
    }

    // MARK: - Saving

    func render(source: CGImage, outputScale: CGFloat) async throws -> CGImage {
        let (size, crop, annotations, background, redaction) = (
            imageSize, crop, annotations, usesBackground ? background : nil, redaction
        )
        return try await Task.detached(priority: .userInitiated) {
            try EditorRenderer.render(
                source: source,
                imageSize: size,
                crop: crop,
                annotations: annotations,
                background: background,
                redaction: redaction,
                outputScale: outputScale
            )
        }.value
    }

    /// Saves the current image and moves on to the next one, or finishes.
    func save() async {
        guard let image, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        commitText()
        do {
            try await results.append(EditedImage(source: source, image: render(source: image, outputScale: 1)))
        } catch {
            loadError = error.localizedDescription
            return
        }
        advance()
    }

    /// Applies the current background (and nothing else) to every remaining image.
    func saveAllWithBackground() async {
        guard !isSaving else { return }
        await save()
        isSaving = true
        defer { isSaving = false }
        let style = background
        let redaction = redaction
        while index < files.count {
            let file = files[index]
            if let edited = try? await Task.detached(priority: .userInitiated, operation: { () throws -> CGImage in
                let image = try ImageEngine.loadImage(file)
                let size = CGSize(width: image.width, height: image.height)
                return try EditorRenderer.render(
                    source: image,
                    imageSize: size,
                    crop: CGRect(origin: .zero, size: size),
                    annotations: [],
                    background: style,
                    redaction: redaction
                )
            }).value {
                results.append(EditedImage(source: file, image: edited))
            }
            index += 1
        }
        finish()
    }

    func skip() {
        advance()
    }

    func finish() {
        let callback = onFinish
        onFinish = nil
        callback?(results)
    }

    private func advance() {
        guard hasMoreFiles else {
            finish()
            return
        }
        index += 1
        load()
    }

    private func load() {
        loadError = nil
        annotations = []
        draft = nil
        textEntry = nil
        undoStack.removeAll()
        redoStack.removeAll()
        do {
            let full = try ImageEngine.loadImage(source)
            image = full
            imageSize = CGSize(width: full.width, height: full.height)
            preview = max(full.width, full.height) > Self.previewSide
                ? try ImageEngine.loadImage(source, maxPixelSize: Self.previewSide) : full
            crop = CGRect(origin: .zero, size: imageSize)
            if cropAspect != .free {
                applyAspect()
            }
        } catch {
            image = nil
            preview = nil
            loadError = error.localizedDescription
        }
    }
}
