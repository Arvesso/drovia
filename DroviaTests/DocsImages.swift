import AppKit
@testable import Drovia
import SwiftUI
import Testing
import UniformTypeIdentifiers

/// Renders the README images into docs/images. Off by default; run `make docs-images`.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["DROVIA_DOCS"] == "1"))
struct DocsImages {
    private let out = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/images")

    private func save(_ image: CGImage, _ name: String) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        // Photos with soft gradients are far smaller as JPEG.
        let data = name.hasSuffix(".jpg")
            ? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.88])
            : rep.representation(using: .png, properties: [:])
        try data!.write(to: out.appendingPathComponent(name))
    }

    @Test func wheels() throws {
        let types: [UTType] = [.png]
        let kinds: [(WheelKind, Int)] = [(.convert, 1), (.tools, 4), (.actions, 1)]
        let view = HStack(spacing: -150) {
            ForEach(kinds, id: \.0) { kind, highlight in
                let model = WheelModel()
                let _ = {
                    model.kind = kind
                    model.items = ActionRegistry.actions(for: kind, types: types).map(\.wheelItem)
                    model.highlighted = highlight
                    model.isPresented = true
                    model.content = DragContent(fileURLs: [URL(fileURLWithPath: "/tmp/photo.png")])
                    model.thumbnail = NSWorkspace.shared.icon(for: .png)
                }()
                ZStack {
                    Circle().fill(.white.opacity(0.78))
                        .frame(width: model.geometry.outerRadius * 2, height: model.geometry.outerRadius * 2)
                        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
                    WheelView(model: model)
                }
            }
        }
        .padding(.vertical, -90)
        .background(LinearGradient(
            colors: [Color(red: 0.86, green: 0.88, blue: 0.97), Color(red: 0.97, green: 0.89, blue: 0.93)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ))
        .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        try save(#require(renderer.cgImage), "wheels.jpg")
    }

    @Test func editorResult() throws {
        let size = CGSize(width: 1400, height: 900)
        let context = try #require(CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        // A mock app window: sidebar, toolbar and content blocks.
        context.setFillColor(RGBA(0xF6F6F8).cgColor); context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(RGBA(0xE9E9EE).cgColor); context.fill(CGRect(x: 0, y: 0, width: 300, height: 900))
        context.setFillColor(RGBA(0xFFFFFF).cgColor); context.fill(CGRect(x: 300, y: 820, width: 1100, height: 80))
        for (index, color) in [0x8B93F8, 0x22D3C5, 0xF28FB0].enumerated() {
            context.setFillColor(RGBA(UInt32(color), alpha: 0.85).cgColor)
            context.fill(CGRect(x: 360 + index * 340, y: 470, width: 300, height: 280))
        }
        for row in 0 ..< 6 {
            context.setFillColor(RGBA(0xD5D5DD).cgColor)
            context.fill(CGRect(x: 40, y: 760 - row * 70, width: 200, height: 22))
            context.fill(CGRect(x: 360, y: 380 - row * 55, width: 900 - row * 90, height: 20))
        }
        let base = try #require(context.makeImage())
        let annotations: [Annotation] = [
            .init(
                shape: .arrow(from: CGPoint(x: 1150, y: 700), to: CGPoint(x: 870, y: 420)),
                color: RGBA(0xFF3B30),
                lineWidth: 9,
                fontSize: 40
            ),
            .init(
                shape: .rectangle(CGRect(x: 690, y: 140, width: 320, height: 300)),
                color: RGBA(0xFF3B30),
                lineWidth: 8,
                fontSize: 40
            ),
            .init(
                shape: .text("New layout", at: CGPoint(x: 1040, y: 720)),
                color: RGBA(0xFF3B30),
                lineWidth: 8,
                fontSize: 52
            ),
            .init(
                shape: .redact(CGRect(x: 40, y: 130, width: 200, height: 92)),
                color: RGBA(0),
                lineWidth: 8,
                fontSize: 40
            ),
            .init(
                shape: .highlight(CGRect(x: 350, y: 560, width: 560, height: 40)),
                color: RGBA(0xFFCC00),
                lineWidth: 8,
                fontSize: 40
            ),
        ]
        let result = try EditorRenderer.render(
            source: base, imageSize: size, crop: CGRect(origin: .zero, size: size), annotations: annotations,
            background: BackgroundStyle(
                fill: .gradient(0),
                padding: 0.07,
                cornerRadius: 0.02,
                shadow: 0.7,
                aspect: .auto
            ),
            redaction: .pixelate, outputScale: 0.75
        )
        try save(result, "editor.png")
    }
}
