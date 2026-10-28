@testable import Drovia
import Testing
import UniformTypeIdentifiers

@MainActor
struct WheelLayoutTests {
    private func ids(_ wheel: WheelKind, _ ext: String, _ layout: WheelLayout) -> [String] {
        ActionRegistry.actions(for: wheel, types: [UTType(filenameExtension: ext)!], layout: layout).map(\.sectorID)
    }

    @Test func customOrderComesFirst() {
        var layout = WheelLayout()
        layout.order[WheelKind.tools.rawValue] = ["tools.metadata", "tools.rotate"]
        let png = ids(.tools, "png", layout)
        #expect(Array(png.prefix(3)) == ["tools.metadata", "tools.rotate", "tools.compress"])
    }

    @Test func orderAppliesToEveryFileKind() {
        var layout = WheelLayout()
        layout.order[WheelKind.tools.rawValue] = ["tools.rotate"]
        // Rotate is a different action for images, PDFs and videos but one sector.
        #expect(ids(.tools, "png", layout).first == "tools.rotate")
        #expect(ids(.tools, "pdf", layout).first == "tools.rotate")
        #expect(ids(.tools, "mov", layout).first == "tools.rotate")
    }

    @Test func hiddenSectorsDisappearEverywhere() {
        var layout = WheelLayout()
        layout.hidden = ["tools.compress"]
        #expect(!ids(.tools, "png", layout).contains("tools.compress"))
        #expect(!ids(.tools, "pdf", layout).contains("tools.compress"))
    }

    @Test func sectorsGroupVariants() {
        let sectors = ActionRegistry.sectors(for: .tools, layout: WheelLayout())
        let compress = sectors.first { $0.id == "tools.compress" }
        #expect(compress?.kinds == [.image, .pdf, .video])
        #expect(Set(sectors.map(\.id)).count == sectors.count)
        let convert = ActionRegistry.sectors(for: .convert, layout: WheelLayout())
        #expect(convert.first { $0.id == "convert.png" }?.kinds == [.image, .pdf])
    }

    @Test func sectorAddedByAnUpdateTakesItsDefaultPlace() {
        let defaults = ActionRegistry.sectors(for: .tools, layout: WheelLayout()).map(\.id)
        // A full order saved before "resize" existed, with the user's own change: metadata moved first.
        var saved = defaults.filter { $0 != "tools.resize" }
        saved.removeAll { $0 == "tools.metadata" }
        saved.insert("tools.metadata", at: 0)
        var layout = WheelLayout()
        layout.order[WheelKind.tools.rawValue] = saved
        let order = ActionRegistry.sectors(for: .tools, layout: layout).map(\.id)
        #expect(order.first == "tools.metadata")
        let compress = order.firstIndex(of: "tools.compress")
        #expect(order.firstIndex(of: "tools.resize") == compress.map { $0 + 1 })
    }

    @Test func unknownIDsInStoredOrderAreIgnored() {
        var layout = WheelLayout()
        layout.order[WheelKind.actions.rawValue] = ["actions.removed-long-ago", "actions.copy"]
        #expect(ids(.actions, "txt", layout).first == "actions.copy")
    }
}
