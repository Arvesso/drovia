import AppKit

/// Transparent overlay that receives drops over the wheel panel and maps them to sectors.
final class WheelDropView: NSView {
    var onHighlight: ((Int?) -> Void)?
    var onDrop: ((Int, NSPasteboard) -> Bool)?

    private let model: WheelModel

    init(model: WheelModel) {
        self.model = model
        super.init(frame: .zero)
        registerForDraggedTypes(DragContent.acceptedTypes)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        update(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        update(sender)
    }

    override func draggingExited(_: (any NSDraggingInfo)?) {
        onHighlight?(nil)
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        sector(for: sender) != nil
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let index = sector(for: sender) else { return false }
        return onDrop?(index, sender.draggingPasteboard) ?? false
    }

    private func update(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let index = sector(for: sender)
        onHighlight?(index)
        guard index != nil else { return [] }
        // Modifier keys narrow the source mask (e.g. ⌘ means move in Finder), so accept whatever is offered.
        let mask = sender.draggingSourceOperationMask
        return [.copy, .generic, .move, .link].first { mask.contains($0) } ?? []
    }

    private func sector(for sender: any NSDraggingInfo) -> Int? {
        let point = convert(sender.draggingLocation, from: nil)
        return model.geometry.sector(at: CGVector(dx: point.x - bounds.midX, dy: point.y - bounds.midY))
    }
}
