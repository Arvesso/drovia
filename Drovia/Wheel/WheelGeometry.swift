import CoreGraphics
import Foundation

/// Pure geometry of a radial wheel: sector 0 is centered at 12 o'clock, the rest follow clockwise.
struct WheelGeometry: Equatable, Sendable {
    /// Extra space around the wheel that still accepts drops, so a quick flick toward a sector counts.
    static let flickMargin: CGFloat = 130

    var sectorCount: Int
    /// Radius of the central hole. Drops inside it select nothing.
    var innerRadius: CGFloat = 64
    var outerRadius: CGFloat = 170

    var sectorAngle: Double {
        2 * .pi / Double(max(sectorCount, 1))
    }

    /// Radius within which drops are accepted at all.
    var catchRadius: CGFloat {
        outerRadius + Self.flickMargin
    }

    var panelSide: CGFloat {
        catchRadius * 2
    }

    /// Center angle of a sector, in radians clockwise from 12 o'clock.
    func centerAngle(of index: Int) -> Double {
        Double(index) * sectorAngle
    }

    /// The sector in the direction of `offset` from the wheel center (y axis pointing up),
    /// or `nil` inside the central hole or beyond the catch radius.
    func sector(at offset: CGVector) -> Int? {
        let distance = hypot(offset.dx, offset.dy)
        guard sectorCount > 0, distance >= innerRadius, distance <= catchRadius else { return nil }
        // atan2(x, y) measures clockwise from the positive y axis.
        var angle = atan2(Double(offset.dx), Double(offset.dy))
        if angle < 0 {
            angle += 2 * .pi
        }
        return Int((angle + sectorAngle / 2) / sectorAngle) % sectorCount
    }
}
