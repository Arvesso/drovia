import SwiftUI

struct GeneralSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle("Open at login", isOn: $settings.launchAtLogin)
            }

            Section {
                Picker("Size", selection: $settings.wheelSize) {
                    ForEach(WheelSize.allCases) { Text($0.title).tag($0) }
                }
                Picker("Show after", selection: $settings.activationDelay) {
                    Text("Instantly").tag(0.0)
                    ForEach([0.1, 0.2, 0.3, 0.5], id: \.self) { delay in
                        Text(
                            Duration.seconds(delay),
                            format: .units(allowed: [.seconds, .milliseconds], width: .abbreviated)
                        )
                        .tag(delay)
                    }
                }
                Toggle("Hide when the modifier key is released", isOn: $settings.hidesWheelOnModifierRelease)
            } header: {
                Text("Wheel")
            } footer: {
                Text("Drag files and hold ⇧ to convert, ⌘ for tools or ⌃ for actions.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Version", value: Bundle.main.appVersion)
            }
        }
        .formStyle(.grouped)
    }
}
