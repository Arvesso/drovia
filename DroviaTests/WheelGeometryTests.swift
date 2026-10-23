import AppKit
@testable import Drovia
import Testing

struct WheelGeometryTests {
    private let four = WheelGeometry(sectorCount: 4)

    @Test func cardinalDirectionsMapClockwiseFromTop() {
        #expect(four.sector(at: CGVector(dx: 0, dy: 100)) == 0)
        #expect(four.sector(at: CGVector(dx: 100, dy: 0)) == 1)
        #expect(four.sector(at: CGVector(dx: 0, dy: -100)) == 2)
        #expect(four.sector(at: CGVector(dx: -100, dy: 0)) == 3)
    }

    @Test func centralHoleSelectsNothing() {
        #expect(four.sector(at: .zero) == nil)
        #expect(four.sector(at: CGVector(dx: 30, dy: 30)) == nil)
    }

    @Test func flickMarginStillSelects() {
        let pastWheel = four.outerRadius + WheelGeometry.flickMargin / 2
        #expect(four.sector(at: CGVector(dx: 0, dy: pastWheel)) == 0)
        #expect(four.sector(at: CGVector(dx: 0, dy: four.catchRadius + 1)) == nil)
    }

    @Test func sectorBoundariesSplitEvenly() {
        let seven = WheelGeometry(sectorCount: 7)
        let half = seven.sectorAngle / 2
        func point(_ angle: Double) -> CGVector {
            CGVector(dx: sin(angle) * 120, dy: cos(angle) * 120)
        }
        #expect(seven.sector(at: point(half - 0.01)) == 0)
        #expect(seven.sector(at: point(half + 0.01)) == 1)
        #expect(seven.sector(at: point(-half + 0.01)) == 0)
        #expect(seven.sector(at: point(-half - 0.01)) == 6)
    }

    @Test func emptyWheelSelectsNothing() {
        #expect(WheelGeometry(sectorCount: 0).sector(at: CGVector(dx: 0, dy: 100)) == nil)
    }
}

struct WheelKindTests {
    @Test func singleModifierSelectsWheel() {
        #expect(WheelKind(modifiers: .shift) == .convert)
        #expect(WheelKind(modifiers: .command) == .tools)
        #expect(WheelKind(modifiers: .control) == .actions)
        #expect(WheelKind(modifiers: .option) == .recipes)
    }

    @Test func irrelevantFlagsAreIgnored() {
        #expect(WheelKind(modifiers: [.shift, .capsLock, .function]) == .convert)
    }

    @Test func combinationsAndOptionSelectNothing() {
        #expect(WheelKind(modifiers: []) == nil)
        #expect(WheelKind(modifiers: [.shift, .command]) == nil)
    }
}
