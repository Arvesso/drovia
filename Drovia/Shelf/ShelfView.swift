import SwiftUI

struct ShelfView: View {
    let model: ShelfModel
    let controller: ShelfController
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 6) {
            header
            if model.items.isEmpty {
                Text("Drop files here")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(model.items) { item in
                            ShelfRow(item: item, controller: controller)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .padding(8)
        .frame(width: ShelfController.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(isTargeted ? 1 : 0)
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            // Nothing to hold (a web link, say): refuse rather than accept and show nothing.
            guard !files.isEmpty else { return false }
            controller.add(files)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(.tint)
                FileDragSource(
                    urls: { model.items.map(\.url) },
                    onBegin: { controller.onDragStart?($0) },
                    onEnd: { operation in
                        controller.onDragEnd?()
                        // As for a single row: moved files leave the shelf.
                        if operation.contains(.move) || operation.contains(.delete) {
                            controller.clear()
                        } else {
                            controller.pruneMissingFiles()
                        }
                    }
                )
            }
            .frame(width: 28, height: 28)
            .help("Drag all files")

            Text("Shelf")
                .font(.headline)
            Text(model.items.count, format: .number)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            WindowDragArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button("Clear", systemImage: "trash") { controller.clear() }
                .help("Clear")
            Button("Close", systemImage: "xmark") { controller.hide() }
                .help("Close")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .frame(height: 32)
        .padding(.horizontal, 4)
    }
}

private struct ShelfRow: View {
    let item: ShelfItem
    let controller: ShelfController
    @State private var thumbnail: NSImage?
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                HStack(spacing: 10) {
                    Group {
                        if let thumbnail {
                            Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.url.lastPathComponent)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let size = item.url.fileSize {
                            Text(Int64(size).formatted(.byteCount(style: .file)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .allowsHitTesting(false)

                FileDragSource(
                    urls: { [item.url] },
                    onBegin: { controller.onDragStart?($0) },
                    onEnd: { operation in
                        controller.onDragEnd?()
                        if operation.contains(.move) || operation.contains(.delete) {
                            controller.remove([item.id])
                        } else {
                            controller.pruneMissingFiles()
                        }
                    },
                    onDoubleClick: { NSWorkspace.shared.open(item.url) },
                    menu: rowMenu
                )
            }

            Button("Remove", systemImage: "xmark.circle.fill") { controller.remove([item.id]) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .opacity(isHovered ? 1 : 0)
        }
        .padding(.horizontal, 6)
        .frame(height: 46)
        .background(isHovered ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.url.lastPathComponent)
        .accessibilityAction(named: Text("Open")) { NSWorkspace.shared.open(item.url) }
        .accessibilityAction(named: Text("Remove from Shelf")) { controller.remove([item.id]) }
        .task(id: item.url) {
            thumbnail = await Thumbnails.image(for: DragContent(fileURLs: [item.url]), side: 34)
        }
    }

    private func rowMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem(title: String(localized: "Open")) { NSWorkspace.shared.open(item.url) })
        menu.addItem(ClosureMenuItem(title: String(localized: "Show in Finder")) {
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: String(localized: "Remove from Shelf")) { controller.remove([item.id]) })
        return menu
    }
}
