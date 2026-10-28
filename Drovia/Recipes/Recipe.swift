import Foundation

/// A user-defined chain of steps, shown on the ⌥ wheel.
struct Recipe: Identifiable, Codable, Equatable, Hashable {
    enum Step: Codable, Equatable, Hashable {
        /// A wheel sector; the variant matching the files at that point runs.
        case action(sectorID: String)
        /// A shortcut from the Shortcuts app, given the files as input.
        case shortcut(name: String)
        /// A zsh script; the files are passed as arguments ("$@").
        case script(String)
    }

    var id = UUID()
    var name: String
    var symbol: String
    var steps: [Step]

    /// The text of its shell-script steps.
    var scripts: [String] {
        steps.compactMap { step in
            guard case let .script(source) = step else { return nil }
            return source
        }
    }

    static let symbols = [
        "wand.and.stars", "sparkles", "bolt", "globe", "paperplane", "photo.stack", "tray.and.arrow.down",
        "doc.on.clipboard", "square.and.arrow.up", "hammer", "leaf", "star",
    ]

    /// Starters for a first launch, so the ⌥ wheel isn't empty.
    static let examples: [Recipe] = [
        Recipe(name: String(localized: "For the Web"), symbol: "globe", steps: [
            .action(sectorID: "tools.resize"), .action(sectorID: "convert.webp"), .action(sectorID: "tools.metadata"),
        ]),
        Recipe(name: String(localized: "Share Light"), symbol: "paperplane", steps: [
            .action(sectorID: "tools.compress"), .action(sectorID: "actions.copy"),
        ]),
    ]
}

@MainActor
extension Recipe.Step {
    var title: String {
        switch self {
        case let .action(sectorID):
            ActionRegistry.all.first { $0.sectorID == sectorID }?.title ?? sectorID
        case let .shortcut(name):
            name
        case .script:
            String(localized: "Shell Script")
        }
    }

    var symbol: String? {
        switch self {
        case let .action(sectorID):
            ActionRegistry.all.first { $0.sectorID == sectorID }?.symbol
        case .shortcut:
            "square.2.layers.3d"
        case .script:
            "terminal"
        }
    }

    var sectorWheel: WheelKind? {
        guard case let .action(sectorID) = self else { return nil }
        return ActionRegistry.all.first { $0.sectorID == sectorID }?.wheel
    }
}
