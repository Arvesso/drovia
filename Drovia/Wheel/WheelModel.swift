import AppKit
import Observation

@MainActor
@Observable
final class WheelModel {
    var kind: WheelKind = .convert
    var items: [WheelItem] = []
    var highlighted: Int?
    var isPresented = false
    var content = DragContent()
    var thumbnail: NSImage?

    var geometry: WheelGeometry {
        WheelGeometry(sectorCount: items.count)
    }

    var highlightedItem: WheelItem? {
        highlighted.flatMap { items.indices.contains($0) ? items[$0] : nil }
    }

    var centerTitle: String {
        highlightedItem?.title ?? kind.title
    }
}
