import UniformTypeIdentifiers

/// All actions, grouped into wheels.
@MainActor
enum ActionRegistry {
    /// Wheel order follows this list. Actions for different file kinds share a wheel,
    /// but only those that fit the dragged files appear.
    static let all: [any DroviaAction] = convert + tools + fileActions

    private static let convert: [any DroviaAction] =
        ImageFormat.convertTargets.map(ImageConvertAction.init)
            + PDFConvertAction.Target.allCases.map(PDFConvertAction.init)
            + DocumentFormat.allCases.map(DocumentConvertAction.init)
            + VideoConvertAction.Target.allCases.map(VideoConvertAction.init)
            + AudioFormat.allCases.map(AudioConvertAction.init)

    private static let tools: [any DroviaAction] = [
        CompressAction(),
        PDFTransformAction(kind: .compress),
        VideoToolAction(kind: .compress),
        VideoToolAction(kind: .mute),
        VideoToolAction(kind: .rotate),
        ResizeAction(),
        EditImageAction(mode: .crop),
        EditImageAction(mode: .annotate),
        EditImageAction(mode: .background),
        RemoveBackgroundAction(),
        RedactAction(),
        RecognizeTextAction(),
        PDFMergeAction(),
        PDFSplitAction(),
        RotateAction(),
        PDFTransformAction(kind: .rotate),
        RemoveMetadataAction(),
        PDFTransformAction(kind: .metadata),
        ChecksumAction(),
    ]

    private static let fileActions: [any DroviaAction] = [
        AirDropAction(),
        FloatAction(),
        CopyAction(),
        MoveAction(),
        CopyPathAction(),
        ZipAction(),
        UnzipAction(),
        TerminalAction(),
        RevealAction(),
        OpenWithAction(),
    ]

    /// Actions of a wheel that can handle all dragged items.
    static func actions(for wheel: WheelKind, types: [UTType]) -> [any DroviaAction] {
        all.filter { $0.wheel == wheel && $0.supports(types) }
    }

    static func action(id: String) -> (any DroviaAction)? {
        all.first { $0.id == id }
    }
}
