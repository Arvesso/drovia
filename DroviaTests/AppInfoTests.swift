@testable import Drovia
import Foundation
import Testing

struct AppInfoTests {
    @Test func appVersionIsReadFromBundle() {
        #expect(Bundle.main.appVersion.hasPrefix("0.1.0"))
    }
}
