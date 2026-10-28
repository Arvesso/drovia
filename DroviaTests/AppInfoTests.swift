@testable import Drovia
import Foundation
import Testing

struct AppInfoTests {
    /// "1.2.3 (45)": the version and build from the bundle, whatever they are.
    @Test func appVersionIsReadFromBundle() throws {
        let version = try #require(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
        #expect(Bundle.main.appVersion.hasPrefix("\(version) ("))
        #expect(!Bundle.main.appVersion.contains("?"))
    }
}
