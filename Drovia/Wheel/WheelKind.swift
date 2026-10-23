import AppKit
import SwiftUI

/// One radial wheel, selected by the modifier key held during a file drag.
enum WheelKind: String, CaseIterable, Sendable {
    case convert
    case tools
    case actions

    /// The wheel for exactly one held modifier: ⇧ Convert, ⌘ Tools, ⌃ Actions.
    /// Combinations (and ⌥, reserved for recipes) select nothing.
    init?(modifiers: NSEvent.ModifierFlags) {
        switch modifiers.intersection([.shift, .command, .control, .option]) {
        case .shift: self = .convert
        case .command: self = .tools
        case .control: self = .actions
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .convert: String(localized: "Convert")
        case .tools: String(localized: "Tools")
        case .actions: String(localized: "Actions")
        }
    }

    var tint: Color {
        switch self {
        case .convert: Color(red: 0.50, green: 0.53, blue: 0.95)
        case .tools: Color(red: 0.16, green: 0.67, blue: 0.62)
        case .actions: Color(red: 0.94, green: 0.48, blue: 0.20)
        }
    }
}

struct WheelItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    /// SF Symbol name; items without a symbol (file formats) render their title large.
    var symbol: String?
}
