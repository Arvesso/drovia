import AppKit
import SwiftUI

/// The welcome window: shown on first launch and from the menu bar.
@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    private let settings: SettingsStore
    private let folderAccess: FolderAccess
    private let history: HistoryStore
    /// Dragging the practice file uses the wheel like any other drag.
    var onPracticeDragStart: (([URL]) -> Void)?
    var onPracticeDragEnd: (() -> Void)?

    private var window: NSWindow?

    init(settings: SettingsStore, folderAccess: FolderAccess, history: HistoryStore) {
        self.settings = settings
        self.folderAccess = folderAccess
        self.history = history
    }

    func showIfNeeded() {
        if !settings.hasCompletedOnboarding {
            show()
        }
    }

    func show() {
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = OnboardingView(
            practiceFile: try? SampleFile.url(),
            history: history,
            onDragStart: { [weak self] in self?.onPracticeDragStart?($0) },
            onDragEnd: { [weak self] in self?.onPracticeDragEnd?() },
            onFinish: { [weak self] in self?.finish() }
        )
        .environment(settings)
        .environment(folderAccess)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 540),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.contentViewController = NSHostingController(rootView: view)
        window.setContentSize(NSSize(width: 660, height: 540))
        window.center()
        window.delegate = self
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        window?.close()
    }

    func windowWillClose(_: Notification) {
        // Closing early counts too: the guide stays available from the menu bar.
        settings.hasCompletedOnboarding = true
        window = nil
    }
}

/// A picture for practising on, created in Application Support on demand.
enum SampleFile {
    static func url() throws -> URL {
        let folder = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Drovia/Practice", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(String(localized: "Drovia Sample") + ".png")
        if !FileManager.default.fileExists(atPath: url.path) {
            try ImageEngine.encode(render(), properties: [:], as: .png, to: url, quality: 1)
        }
        return url
    }

    /// A gradient card with the app's dashed-ring motif.
    private static func render() throws -> CGImage {
        let size = CGSize(width: 1200, height: 800)
        guard let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw ImageEngineError.cannotWrite(.png) }
        let colors = BackgroundFill.gradients[0]
        let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [colors.0.cgColor, colors.1.cgColor] as CFArray,
            locations: [0, 1]
        )!
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
        context.setLineWidth(36)
        context.setLineCap(.round)
        context.setLineDash(phase: 0, lengths: [180, 90])
        context.addArc(center: CGPoint(x: 600, y: 400), radius: 220, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        context.strokePath()
        context.setFillColor(CGColor(gray: 1, alpha: 0.95))
        context.fillEllipse(in: CGRect(x: 545, y: 345, width: 110, height: 110))
        return try context.makeImage().orThrow(ImageEngineError.cannotWrite(.png))
    }
}
