import AppKit
import SwiftUI

/// Short-lived glass capsule near the cursor confirming what happened.
@MainActor
final class ToastPresenter {
    private let model = ToastModel()
    private var hideTask: Task<Void, Never>?

    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: ToastView(model: model))
        return panel
    }()

    func show(_ title: String, subtitle: String? = nil, symbol: String = "checkmark.circle.fill", tint: Color) {
        model.title = title
        model.subtitle = subtitle
        model.symbol = symbol
        model.tint = tint

        let mouse = NSEvent.mouseLocation
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 24))
        panel.orderFrontRegardless()
        model.isVisible = true

        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            model.isVisible = false
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }
}

@MainActor
@Observable
private final class ToastModel {
    var title = ""
    var subtitle: String?
    var symbol = ""
    var tint = Color.accentColor
    var isVisible = false
}

private struct ToastView: View {
    let model: ToastModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(model.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.title)
                    .font(.system(size: 13, weight: .semibold))
                if let subtitle = model.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: Capsule())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(model.isVisible ? 1 : 0)
        .offset(y: model.isVisible ? 0 : -6)
        .animation(.snappy(duration: 0.2), value: model.isVisible)
    }
}
