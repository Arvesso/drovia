import UniformTypeIdentifiers

/// All actions, grouped into wheels.
@MainActor
enum ActionRegistry {
    static let all: [any DroviaAction] = ImageFormat.convertTargets.map(ImageConvertAction.init) + [
        CompressAction(),
        RemoveMetadataAction(),
        ResizeAction(),
        RotateAction(),
        AirDropAction(),
        CopyAction(),
        MoveAction(),
        CopyPathAction(),
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
