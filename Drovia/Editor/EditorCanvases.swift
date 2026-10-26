import SwiftUI

/// Maps between image pixels and view points for an image fitted (centered) into a container.
struct FitTransform {
    let scale: CGFloat
    let origin: CGPoint

    init(content: CGSize, container: CGSize, inset: CGFloat = 28) {
        let available = CGSize(width: max(1, container.width - inset * 2), height: max(1, container.height - inset * 2))
        scale = min(available.width / max(content.width, 1), available.height / max(content.height, 1))
        origin = CGPoint(
            x: (container.width - content.width * scale) / 2,
            y: (container.height - content.height * scale) / 2
        )
    }

    func view(_ point: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + point.x * scale, y: origin.y + point.y * scale)
    }

    func view(_ rect: CGRect) -> CGRect {
        CGRect(origin: view(rect.origin), size: CGSize(width: rect.width * scale, height: rect.height * scale))
    }

    func image(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - origin.x) / scale, y: (point.y - origin.y) / scale)
    }
}

// MARK: - Crop

struct CropCanvas: View {
    let model: EditorModel
    @State private var drag: (handle: CropHandle, initial: CGRect, start: CGPoint)?

    var body: some View {
        GeometryReader { geometry in
            let fit = FitTransform(content: model.imageSize, container: geometry.size)
            let imageRect = fit.view(CGRect(origin: .zero, size: model.imageSize))
            let cropRect = fit.view(model.crop)
            ZStack(alignment: .topLeading) {
                if let preview = model.preview {
                    Image(decorative: preview, scale: 1)
                        .resizable()
                        .frame(width: imageRect.width, height: imageRect.height)
                        .position(x: imageRect.midX, y: imageRect.midY)
                }
                Path { path in
                    path.addRect(imageRect)
                    path.addRect(cropRect)
                }
                .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))

                Path { path in
                    for third in [1.0 / 3, 2.0 / 3] {
                        path.move(to: CGPoint(x: cropRect.minX + cropRect.width * third, y: cropRect.minY))
                        path.addLine(to: CGPoint(x: cropRect.minX + cropRect.width * third, y: cropRect.maxY))
                        path.move(to: CGPoint(x: cropRect.minX, y: cropRect.minY + cropRect.height * third))
                        path.addLine(to: CGPoint(x: cropRect.maxX, y: cropRect.minY + cropRect.height * third))
                    }
                }
                .stroke(.white.opacity(0.45), lineWidth: 0.5)

                Path { $0.addRect(cropRect) }
                    .stroke(.white, lineWidth: 1.5)

                ForEach(Array(corners(of: cropRect).enumerated()), id: \.offset) { _, corner in
                    Circle()
                        .fill(.white)
                        .shadow(radius: 2)
                        .frame(width: 12, height: 12)
                        .position(corner)
                }

                Text("\(Int(model.crop.width)) × \(Int(model.crop.height))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.6), in: Capsule())
                    .position(x: cropRect.midX, y: min(cropRect.maxY + 14, geometry.size.height - 10))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if drag == nil {
                            model.recordUndo()
                            drag = (
                                handle(at: value.startLocation, crop: cropRect),
                                model.crop,
                                fit.image(value.startLocation)
                            )
                        }
                        guard let drag else { return }
                        model.dragCrop(
                            drag.handle,
                            from: drag.initial,
                            start: drag.start,
                            to: fit.image(value.location)
                        )
                    }
                    .onEnded { _ in drag = nil }
            )
        }
    }

    private func corners(of rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
        ]
    }

    private func handle(at point: CGPoint, crop: CGRect) -> CropHandle {
        let reach: CGFloat = 16
        let handles: [(CropHandle, CGPoint)] = [
            (.topLeft, CGPoint(x: crop.minX, y: crop.minY)), (.topRight, CGPoint(x: crop.maxX, y: crop.minY)),
            (.bottomLeft, CGPoint(x: crop.minX, y: crop.maxY)), (.bottomRight, CGPoint(x: crop.maxX, y: crop.maxY)),
        ]
        if let corner = handles.first(where: { hypot($0.1.x - point.x, $0.1.y - point.y) < reach }) {
            return corner.0
        }
        // A crop covering the whole image can't move, so dragging inside it draws a new one.
        let isWholeImage = model.crop.size == model.imageSize
        return crop.contains(point) && !isWholeImage ? .move : .new
    }
}

// MARK: - Annotate

struct AnnotationCanvas: View {
    let model: EditorModel
    @State private var start: CGPoint?
    @FocusState private var isTyping: Bool

    var body: some View {
        GeometryReader { geometry in
            let fit = FitTransform(content: model.crop.size, container: geometry.size)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    guard let preview = model.preview else { return }
                    let crop = model.crop
                    let annotations = model.annotations + (model.draft.map { [$0] } ?? [])
                    context.withCGContext { cg in
                        cg.translateBy(x: fit.origin.x, y: fit.origin.y)
                        cg.scaleBy(x: fit.scale, y: fit.scale)
                        cg.translateBy(x: -crop.minX, y: -crop.minY)
                        cg.clip(to: crop)
                        AnnotationDrawer.drawImage(
                            preview,
                            in: CGRect(origin: .zero, size: model.imageSize),
                            context: cg
                        )
                        AnnotationDrawer.draw(
                            annotations, source: preview, sourceScale: CGFloat(preview.width) / model.imageSize.width,
                            redaction: model.redaction, in: cg
                        )
                    }
                }

                if let entry = model.textEntry {
                    let point = fit.view(CGPoint(
                        x: entry.point.x - model.crop.minX,
                        y: entry.point.y - model.crop.minY
                    ))
                    TextField("Type text", text: Binding(
                        get: { model.textEntry?.text ?? "" },
                        set: { model.textEntry?.text = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 260)
                    .offset(x: point.x, y: point.y)
                    .focused($isTyping)
                    .onSubmit { model.commitText() }
                    .onAppear { isTyping = true }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let point = imagePoint(value.location, fit: fit)
                        if start == nil {
                            if model.textEntry != nil {
                                model.commitText()
                            }
                            start = imagePoint(value.startLocation, fit: fit)
                            model.beginAnnotation(at: start!)
                        }
                        model.updateAnnotation(from: start!, to: point)
                    }
                    .onEnded { value in
                        model.endAnnotation(at: start ?? imagePoint(value.location, fit: fit))
                        start = nil
                    }
            )
            .onContinuousHover { phase in
                if case .active = phase, model.tool == .text {
                    NSCursor.iBeam.set()
                } else {
                    NSCursor.crosshair.set()
                }
            }
        }
    }

    private func imagePoint(_ point: CGPoint, fit: FitTransform) -> CGPoint {
        let local = fit.image(point)
        return CGPoint(x: local.x + model.crop.minX, y: local.y + model.crop.minY)
    }
}

// MARK: - Background

struct BackgroundPreview: View {
    let model: EditorModel
    @State private var rendered: CGImage?

    var body: some View {
        ZStack {
            if let rendered {
                Image(decorative: rendered, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .padding(28)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: model.snapshot) {
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled, let preview = model.preview else { return }
            rendered = try? await model.render(
                source: preview,
                outputScale: CGFloat(preview.width) / model.imageSize.width
            )
        }
    }
}
