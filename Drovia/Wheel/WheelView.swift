import SwiftUI

struct WheelView: View {
    let model: WheelModel

    var body: some View {
        let geometry = model.geometry
        ZStack {
            // Nearly invisible fill so the window server routes drags in the flick margin to us.
            Circle()
                .fill(Color.black.opacity(0.002))

            Circle()
                .fill(.clear)
                .frame(width: geometry.outerRadius * 2, height: geometry.outerRadius * 2)
                .glassEffect(.regular, in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)

            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                SectorView(
                    item: item,
                    index: index,
                    geometry: geometry,
                    tint: model.kind.tint,
                    isHighlighted: model.highlighted == index
                )
            }

            CenterView(model: model)
                .frame(width: geometry.innerRadius * 2 - 12, height: geometry.innerRadius * 2 - 12)

            if model.isKeyboardMode {
                KeyboardHints(model: model)
                    .offset(y: geometry.outerRadius + 44)
            }
        }
        .frame(width: geometry.panelSide, height: geometry.panelSide)
        .scaleEffect(model.isPresented ? 1 : 0.6)
        .opacity(model.isPresented ? 1 : 0)
        .animation(.spring(duration: 0.3, bounce: 0.3), value: model.isPresented)
        .animation(.snappy(duration: 0.14), value: model.highlighted)
        .animation(.snappy(duration: 0.2), value: model.kind)
    }
}

private struct SectorView: View {
    let item: WheelItem
    let index: Int
    let geometry: WheelGeometry
    let tint: Color
    let isHighlighted: Bool

    var body: some View {
        let angle = geometry.centerAngle(of: index)
        let half = geometry.sectorAngle / 2
        let shape = AnnularSector(
            startAngle: angle - half,
            endAngle: angle + half,
            innerRadius: geometry.innerRadius + 6,
            outerRadius: geometry.outerRadius - 6
        )
        let labelRadius = (geometry.innerRadius + geometry.outerRadius) / 2

        ZStack {
            shape
                .fill(isHighlighted ? AnyShapeStyle(tint) : AnyShapeStyle(.primary.opacity(0.06)))
            shape
                .stroke(isHighlighted ? Color.clear : Color.primary.opacity(0.08), lineWidth: 1)

            SectorLabel(item: item)
                .foregroundStyle(isHighlighted ? Color.white : Color.primary)
                .offset(x: labelRadius * sin(angle), y: -labelRadius * cos(angle))
        }
        .scaleEffect(isHighlighted ? 1.04 : 1)
    }
}

private struct SectorLabel: View {
    let item: WheelItem

    var body: some View {
        if let symbol = item.symbol {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                Text(item.title)
                    .font(.system(size: 9.5, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 80)
        } else {
            Text(item.title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
        }
    }
}

/// Which wheels exist and how to drive them, shown below the wheel in keyboard mode.
private struct KeyboardHints: View {
    let model: WheelModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(WheelKind.allCases, id: \.self) { kind in
                    Text("\(kind.modifierSymbol) \(kind.title)")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .foregroundStyle(kind == model.kind ? Color.white : .primary)
                        .background(kind == model.kind ? kind.tint : .clear, in: Capsule())
                        .opacity(model.availableKinds.contains(kind) ? 1 : 0.35)
                }
            }
            .padding(4)
            .glassEffect(.regular, in: Capsule())

            Text("Tab — next wheel  ·  ← → — choose  ·  ↩ or 1–9 — run  ·  Esc — close")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
    }
}

private struct CenterView: View {
    let model: WheelModel

    var body: some View {
        ZStack {
            Circle()
                .fill(.background.opacity(0.55))

            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    if let thumbnail = model.thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 34, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    if model.content.itemCount > 1 {
                        Text(model.content.itemCount, format: .number)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 15, minHeight: 15)
                            .background(model.kind.tint, in: Capsule())
                            .offset(x: 7, y: -5)
                    }
                }
                Text(model.centerTitle)
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.interpolate)
            }
            .padding(8)
        }
    }
}

/// A ring segment between two angles (radians, clockwise from 12 o'clock) with rounded corners.
struct AnnularSector: Shape {
    var startAngle: Double
    var endAngle: Double
    var innerRadius: CGFloat
    var outerRadius: CGFloat
    var gap: CGFloat = 5
    var cornerRadius: CGFloat = 9

    func path(in rect: CGRect) -> Path {
        // Shrink the segment by the corner radius, then stroke it with a round join of that width.
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = outerRadius - cornerRadius
        let inner = innerRadius + cornerRadius
        let halfGap = gap / 2 + cornerRadius
        // SwiftUI angles start at 3 o'clock and grow clockwise on screen.
        func screen(_ angle: Double) -> Angle {
            .radians(angle - .pi / 2)
        }

        var path = Path()
        path.addArc(
            center: center, radius: outer,
            startAngle: screen(startAngle + halfGap / outer), endAngle: screen(endAngle - halfGap / outer),
            clockwise: false
        )
        path.addArc(
            center: center, radius: inner,
            startAngle: screen(endAngle - halfGap / inner), endAngle: screen(startAngle + halfGap / inner),
            clockwise: true
        )
        path.closeSubpath()
        return path.strokedPath(StrokeStyle(lineWidth: cornerRadius * 2, lineJoin: .round)).union(path)
    }
}
