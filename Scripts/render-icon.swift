// Renders the Drovia app icon into an .appiconset folder.
// Usage: swift Scripts/render-icon.swift <path/to/AppIcon.appiconset>
import AppKit

let outputDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// Draws the icon on a 1024×1024 canvas following the macOS icon grid (824pt body, 100pt margin).
func drawIcon(in ctx: CGContext) {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Drop shadow + background gradient.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, alpha: 0.35))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x23263A))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(0x2E3247), color(0x1B1D2B)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()

    let center = CGPoint(x: 512, y: 512)

    // Dashed ring.
    ctx.saveGState()
    ctx.setStrokeColor(color(0x9BA3F7))
    ctx.setLineWidth(34)
    ctx.setLineCap(.round)
    ctx.setLineDash(phase: 40, lengths: [210, 70, 120, 70, 260, 70, 150, 70])
    ctx.addArc(center: center, radius: 262, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()

    // Inner disc.
    ctx.setFillColor(color(0x474B5E))
    ctx.fillEllipse(in: CGRect(x: center.x - 130, y: center.y - 130, width: 260, height: 260))

    // Diamond.
    let d: CGFloat = 92
    ctx.move(to: CGPoint(x: center.x, y: center.y + d))
    ctx.addLine(to: CGPoint(x: center.x + d, y: center.y))
    ctx.addLine(to: CGPoint(x: center.x, y: center.y - d))
    ctx.addLine(to: CGPoint(x: center.x - d, y: center.y))
    ctx.closePath()
    ctx.setFillColor(color(0xD3D6FB))
    ctx.fillPath()

    // Core dot.
    ctx.setFillColor(color(0x7F88F2))
    ctx.fillEllipse(in: CGRect(x: center.x - 30, y: center.y - 30, width: 60, height: 60))
}

func render(pixels: Int) -> Data {
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(in: ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try render(pixels: size * scale).write(to: outputDir.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": name])
    }
}

let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outputDir.appendingPathComponent("Contents.json"))
print("Rendered \(images.count) icons into \(outputDir.path)")
