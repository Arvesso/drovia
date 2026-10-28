import AppKit

/// Drovia's menu bar glyph, in the spirit of the app icon: a wheel of sectors with one chosen (the one
/// at the top, a little bolder) around the file being dropped (the diamond). A template image, so the
/// menu bar tints it for light and dark appearances and when it's highlighted.
@MainActor
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            draw(in: rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Drovia"
        return image
    }()

    private nonisolated static let sectors = 6

    nonisolated static func draw(in rect: NSRect) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width * 0.34
        let lineWidth = rect.width * 0.105
        NSColor.black.setStroke()
        NSColor.black.setFill()

        // Sectors clockwise from 12 o'clock, as on the wheel. Round caps reach past an arc's ends, so the
        // gap leaves room for them plus a visible space.
        let span = 360 / CGFloat(sectors)
        let capAngle = lineWidth / radius * 180 / .pi
        let gap = capAngle + 13
        for index in 0 ..< sectors {
            let middle = 90 - CGFloat(index) * span
            // The chosen sector (top) is bolder and sits a little further out, like a hovered one on the wheel.
            let isChosen = index == 0
            let arc = NSBezierPath()
            arc.appendArc(
                withCenter: center, radius: isChosen ? radius + rect.width * 0.06 : radius,
                startAngle: middle - span / 2 + gap / 2, endAngle: middle + span / 2 - gap / 2
            )
            arc.lineWidth = isChosen ? lineWidth * 1.6 : lineWidth
            arc.lineCapStyle = .round
            arc.stroke()
        }

        // The file in the middle.
        let half = rect.width * 0.13
        let diamond = NSBezierPath()
        diamond.move(to: NSPoint(x: center.x, y: center.y + half))
        diamond.line(to: NSPoint(x: center.x + half, y: center.y))
        diamond.line(to: NSPoint(x: center.x, y: center.y - half))
        diamond.line(to: NSPoint(x: center.x - half, y: center.y))
        diamond.close()
        diamond.fill()
    }
}
