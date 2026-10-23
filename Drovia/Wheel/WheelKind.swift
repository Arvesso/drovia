import AppKit
import SwiftUI

/// One radial wheel, selected by the modifier key held during a file drag.
enum WheelKind: String, CaseIterable, Sendable {
    case convert
    case tools
    case actions
    case recipes

    /// The wheel for exactly one held modifier: ⇧ Convert, ⌘ Tools, ⌃ Actions, ⌥ Recipes.
    /// Combinations select nothing.
    init?(modifiers: NSEvent.ModifierFlags) {
        switch modifiers.intersection([.shift, .command, .control, .option]) {
        case .shift: self = .convert
        case .command: self = .tools
        case .control: self = .actions
        case .option: self = .recipes
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .convert: String(localized: "Convert")
        case .tools: String(localized: "Tools")
        case .actions: String(localized: "Actions")
        case .recipes: String(localized: "Recipes")
        }
    }

    var modifierSymbol: String {
        switch self {
        case .convert: "⇧"
        case .tools: "⌘"
        case .actions: "⌃"
        case .recipes: "⌥"
        }
    }

    /// Shown when no action of this wheel fits the dragged files.
    var emptyMessage: String {
        switch self {
        case .convert: String(localized: "Can't convert these files")
        case .tools: String(localized: "No tools for these files")
        case .actions: String(localized: "No actions for these files")
        case .recipes: String(localized: "No recipes for these files")
        }
    }

    var tint: Color {
        switch self {
        case .convert: Color(red: 0.50, green: 0.53, blue: 0.95)
        case .tools: Color(red: 0.16, green: 0.67, blue: 0.62)
        case .actions: Color(red: 0.94, green: 0.48, blue: 0.20)
        case .recipes: Color(red: 0.85, green: 0.36, blue: 0.62)
        }
    }
}

struct WheelItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    /// SF Symbol name; items without a symbol (file formats) render their title large.
    var symbol: String?
}
