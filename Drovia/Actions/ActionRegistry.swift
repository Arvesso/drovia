import UniformTypeIdentifiers

/// The user's arrangement of wheel sectors.
struct WheelLayout: Equatable, Codable {
    /// Sector order per wheel (`WheelKind.rawValue` → sector IDs). Sectors missing here keep their default place.
    var order: [String: [String]] = [:]
    var hidden: Set<String> = []

    init(order: [String: [String]] = [:], hidden: Set<String> = []) {
        self.order = order
        self.hidden = hidden
    }

    /// Missing fields keep their defaults, so adding one later doesn't reset the user's layout.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        order = try container.decodeIfPresent([String: [String]].self, forKey: .order) ?? [:]
        hidden = try container.decodeIfPresent(Set<String>.self, forKey: .hidden) ?? []
    }
}

/// A sector as shown in the wheel editor, standing for all its per-file-kind variants.
struct WheelSector: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String?
    let kinds: [FileKind]
}

/// Broad file kinds, used to describe which files a sector applies to.
enum FileKind: CaseIterable {
    case image, pdf, document, video, audio, archive, other

    /// Several samples per kind: an action may skip one of them (PNG → PNG isn't offered).
    var sampleTypes: [UTType] {
        switch self {
        case .image: [.png, .jpeg]
        case .pdf: [.pdf]
        case .document: [.rtf, UTType("org.openxmlformats.wordprocessingml.document") ?? .rtf]
        case .video: [.mpeg4Movie, .quickTimeMovie]
        case .audio: [.mp3, .wav]
        case .archive: [.zip]
        case .other: [UTType("com.apple.disk-image-udif") ?? .data]
        }
    }

    var title: String {
        switch self {
        case .image: String(localized: "Images")
        case .pdf: "PDF"
        case .document: String(localized: "Documents")
        case .video: String(localized: "Video")
        case .audio: String(localized: "Audio")
        case .archive: String(localized: "Archives")
        case .other: String(localized: "Other files")
        }
    }
}

/// All actions, grouped into wheels.
@MainActor
enum ActionRegistry {
    /// Default sector order follows the first appearance of each sector in this list, so variants of a
    /// sector are listed together. Only actions that fit the dragged files appear on a wheel.
    static let all: [any DroviaAction] = convert + tools + fileActions

    private static let convert: [any DroviaAction] =
        ImageFormat.convertTargets.map(ImageConvertAction.init)
            + DocumentFormat.allCases.map(DocumentConvertAction.init)
            + PDFConvertAction.Target.allCases.map(PDFConvertAction.init)
            + VideoConvertAction.Target.allCases.map(VideoConvertAction.init)
            + AudioFormat.allCases.map(AudioConvertAction.init)

    private static let tools: [any DroviaAction] = [
        CompressAction(),
        PDFTransformAction(kind: .compress),
        VideoToolAction(kind: .compress),
        ResizeAction(),
        EditImageAction(mode: .crop),
        EditImageAction(mode: .annotate),
        EditImageAction(mode: .background),
        RemoveBackgroundAction(),
        RedactAction(),
        RecognizeTextAction(),
        PDFMergeAction(),
        PDFSplitAction(),
        VideoToolAction(kind: .mute),
        RotateAction(),
        PDFTransformAction(kind: .rotate),
        VideoToolAction(kind: .rotate),
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

    /// Visible actions of a wheel that can handle all dragged items, in the user's order.
    static func actions(
        for wheel: WheelKind,
        types: [UTType],
        layout: WheelLayout = WheelLayout(),
        recipes: [Recipe] = []
    ) -> [any DroviaAction] {
        if wheel == .recipes {
            return recipes.map(RecipeAction.init).filter { $0.supports(types) }
        }
        let order = sectorOrder(for: wheel, layout: layout)
        return all
            .filter { $0.wheel == wheel && !layout.hidden.contains($0.sectorID) && $0.supports(types) }
            .sorted { (order[$0.sectorID] ?? .max) < (order[$1.sectorID] ?? .max) }
    }

    static func action(id: String, recipes: [Recipe] = []) -> (any DroviaAction)? {
        all.first { $0.id == id } ?? recipes.map(RecipeAction.init).first { $0.id == id }
    }

    /// Every sector of a wheel in the user's order, for the wheel editor.
    static func sectors(for wheel: WheelKind, layout: WheelLayout) -> [WheelSector] {
        let order = sectorOrder(for: wheel, layout: layout)
        var seen: Set<String> = []
        return all.filter { $0.wheel == wheel && seen.insert($0.sectorID).inserted }
            .map { first in
                let variants = all.filter { $0.sectorID == first.sectorID }
                let kinds = FileKind.allCases
                    .filter { kind in kind.sampleTypes.contains { type in variants.contains { $0.supports([type]) } } }
                return WheelSector(id: first.sectorID, title: first.title, symbol: first.symbol, kinds: kinds)
            }
            .sorted { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
    }

    /// Rank of each sector: the user's order first, then new sectors in their default place.
    private static func sectorOrder(for wheel: WheelKind, layout: WheelLayout) -> [String: Int] {
        var seen: Set<String> = []
        let defaults = all.filter { $0.wheel == wheel && seen.insert($0.sectorID).inserted }.map(\.sectorID)
        let custom = (layout.order[wheel.rawValue] ?? []).filter(defaults.contains)
        let ordered = custom + defaults.filter { !custom.contains($0) }
        return Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1, $0) })
    }
}
