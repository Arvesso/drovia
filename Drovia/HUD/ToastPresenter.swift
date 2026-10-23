import AppKit
import SwiftUI

/// Glass capsule near the cursor: progress while an action runs, then a summary.
/// Clicking a summary reveals the produced files in Finder.
@MainActor
final class ToastPresenter {
    private static let displayDuration = Duration.seconds(2.4)

    private let model = ToastModel()
    private var hideTask: Task<Void, Never>?
    private var revealURLs: [URL] = []

    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 72),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: ToastView(model: model) { [weak self] in self?.revealAndHide() })
        return panel
    }()

    var isShowingProgress: Bool {
        model.isVisible && model.progress != nil
    }

    func show(
        _ title: String,
        detail: String? = nil,
        symbol: String = "checkmark.circle.fill",
        tint: Color,
        reveal: [URL] = []
    ) {
        present(title: title, detail: detail, symbol: symbol, tint: tint, progress: nil, reveal: reveal)
        scheduleHide()
    }

    func showError(_ title: String, detail: String?, reveal: [URL] = []) {
        show(title, detail: detail, symbol: "exclamationmark.triangle.fill", tint: .orange, reveal: reveal)
    }

    /// Stays up until replaced by a summary or hidden.
    func showProgress(_ title: String, fraction: Double, tint: Color) {
        hideTask?.cancel()
        let percent = fraction.formatted(.percent.precision(.fractionLength(0)))
        present(title: title, detail: percent, symbol: "", tint: tint, progress: fraction, reveal: [])
    }

    func hide() {
        hideTask?.cancel()
        model.isVisible = false
        hideTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }

    private func present(
        title: String,
        detail: String?,
        symbol: String,
        tint: Color,
        progress: Double?,
        reveal: [URL]
    ) {
        model.title = title
        model.detail = detail
        model.symbol = symbol
        model.tint = tint
        model.progress = progress
        model.isClickable = !reveal.isEmpty
        revealURLs = reveal
        panel.ignoresMouseEvents = reveal.isEmpty

        if !model.isVisible {
            let mouse = NSEvent.mouseLocation
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 24))
        }
        panel.orderFrontRegardless()
        model.isVisible = true
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: Self.displayDuration)
            guard !Task.isCancelled else { return }
            hide()
        }
    }

    private func revealAndHide() {
        guard !revealURLs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(revealURLs)
        hide()
    }
}

@MainActor
@Observable
private final class ToastModel {
    var title = ""
    var detail: String?
    var symbol = ""
    var tint = Color.accentColor
    var progress: Double?
    var isClickable = false
    var isVisible = false
}

private struct ToastView: View {
    let model: ToastModel
    let onClick: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let progress = model.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(model.tint)
            } else {
                Image(systemName: model.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(model.tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(model.title)
                    .font(.system(size: 13, weight: .semibold))
                if let detail = model.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .lineLimit(1)
            .truncationMode(.middle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(model.isClickable ? .regular.interactive() : .regular, in: Capsule())
        .contentShape(Capsule())
        .onTapGesture(perform: onClick)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(model.isVisible ? 1 : 0)
        .offset(y: model.isVisible ? 0 : -6)
        .animation(.snappy(duration: 0.2), value: model.isVisible)
    }
}
