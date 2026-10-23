/// Placeholder wheel contents. Replaced by the action registry in phase 2.
enum WheelCatalog {
    static func items(for kind: WheelKind) -> [WheelItem] {
        switch kind {
        case .convert:
            ["PNG", "WEBP", "HEIC", "TIFF", "AVIF", "BMP", "PDF"].map {
                WheelItem(id: "convert.\($0.lowercased())", title: $0)
            }
        case .tools:
            [
                WheelItem(
                    id: "tools.compress",
                    title: String(localized: "Compress"),
                    symbol: "arrow.down.right.and.arrow.up.left"
                ),
                WheelItem(id: "tools.metadata", title: String(localized: "Metadata"), symbol: "tag.slash"),
                WheelItem(id: "tools.edit", title: String(localized: "Edit"), symbol: "slider.horizontal.3"),
                WheelItem(id: "tools.annotate", title: String(localized: "Annotate"), symbol: "pencil.tip"),
                WheelItem(id: "tools.addbg", title: String(localized: "Add BG"), symbol: "photo.on.rectangle"),
                WheelItem(id: "tools.crop", title: String(localized: "Crop"), symbol: "crop"),
                WheelItem(id: "tools.redact", title: String(localized: "Redact"), symbol: "eye.slash"),
            ]
        case .actions:
            [
                WheelItem(id: "actions.airdrop", title: "AirDrop", symbol: "dot.radiowaves.left.and.right"),
                WheelItem(id: "actions.float", title: String(localized: "Float"), symbol: "pin"),
                WheelItem(id: "actions.copy", title: String(localized: "Copy"), symbol: "doc.on.doc"),
                WheelItem(id: "actions.move", title: String(localized: "Move"), symbol: "folder"),
                WheelItem(id: "actions.copypath", title: String(localized: "Copy Path"), symbol: "doc.text"),
                WheelItem(id: "actions.terminal", title: String(localized: "Terminal"), symbol: "apple.terminal"),
            ]
        }
    }
}
