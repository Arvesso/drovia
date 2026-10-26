import AppKit
@testable import Drovia
import Testing

@MainActor
struct ToastPlacementTests {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
    private let size = CGSize(width: 360, height: 72)

    @Test func sitsBelowThePointer() {
        let origin = ToastPresenter.origin(for: size, near: NSPoint(x: 700, y: 500), screens: [screen])
        #expect(origin == NSPoint(x: 520, y: 404))
    }

    @Test func flipsAboveThePointerAtTheBottomEdge() {
        let origin = ToastPresenter.origin(for: size, near: NSPoint(x: 700, y: 40), screens: [screen])
        #expect(origin.y == 64)
    }

    @Test func staysOnScreenAtTheSides() {
        let left = ToastPresenter.origin(for: size, near: NSPoint(x: 10, y: 500), screens: [screen])
        let right = ToastPresenter.origin(for: size, near: NSPoint(x: 1435, y: 500), screens: [screen])
        #expect(left.x == 0)
        #expect(right.x == screen.maxX - size.width)
    }

    @Test func usesTheScreenUnderThePointer() {
        let second = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let origin = ToastPresenter.origin(for: size, near: NSPoint(x: 1450, y: 500), screens: [screen, second])
        #expect(origin.x == second.minX)
    }
}
