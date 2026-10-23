import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView()
            }
        }
        .frame(width: 480, height: 320)
    }
}

private struct GeneralSettingsView: View {
    var body: some View {
        Form {
            LabeledContent("Version", value: Bundle.main.appVersion)
        }
        .formStyle(.grouped)
    }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
