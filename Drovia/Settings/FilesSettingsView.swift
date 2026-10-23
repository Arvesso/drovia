import SwiftUI

struct FilesSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Saving") {
                Picker("Save results", selection: $settings.outputLocation) {
                    ForEach(OutputLocation.allCases) { Text($0.title).tag($0) }
                }
                if settings.outputLocation == .folder {
                    LabeledContent("Folder") {
                        HStack {
                            Text(settings.outputFolderPath.map { ($0 as NSString).abbreviatingWithTildeInPath }
                                ?? String(localized: "None"))
                                .foregroundStyle(.secondary)
                                .truncationMode(.middle)
                                .lineLimit(1)
                            Button("Choose…") {
                                Task {
                                    if let url = await FolderPanel.choose(prompt: String(localized: "Choose")) {
                                        settings.outputFolderPath = url.path
                                    }
                                }
                            }
                        }
                    }
                }
                TextField("File name", text: $settings.fileNameTemplate, prompt: Text(NamingTemplate.defaultTemplate))
                Toggle("Move originals to the Trash", isOn: $settings.trashesOriginals)
                Toggle("Add results to the shelf", isOn: $settings.addsResultsToShelf)
            }

            Section {
                LabeledContent("Quality") {
                    HStack {
                        Slider(value: $settings.imageQuality, in: 0.3 ... 1, step: 0.05)
                        Text(settings.imageQuality, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                Toggle("Keep metadata when converting", isOn: $settings.keepsMetadataOnConvert)
            } header: {
                Text("Images")
            } footer: {
                Text("File name tokens: {name}, {action}, {date}. Conversions keep the original name.")
                    .foregroundStyle(.secondary)
            }

            Section("Tools") {
                Picker("Compress: limit size to", selection: $settings.compressMaxDimension) {
                    Text("Original size").tag(0)
                    ForEach([1920, 2560, 3840], id: \.self) { Text("\($0) px").tag($0) }
                }
                Toggle("Compress: remove metadata", isOn: $settings.compressRemovesMetadata)
                Picker("Resize to", selection: $settings.resizePreset) {
                    ForEach(ResizePreset.allCases) { Text($0.title).tag($0) }
                }
                Picker("Metadata: remove", selection: $settings.metadataRemoval) {
                    ForEach(MetadataRemoval.allCases) { Text($0.title).tag($0) }
                }
            }

            Section {
                Toggle("Remove BG: crop to the subject", isOn: $settings.removeBackgroundCrops)
                Picker("Redact with", selection: $settings.redactionStyle) {
                    ForEach(RedactionStyle.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Redact faces", isOn: $settings.redactsFaces)
                Toggle("Redact emails, phone numbers, links and card numbers", isOn: $settings.redactsPersonalText)
                Toggle("Redact QR codes and barcodes", isOn: $settings.redactsCodes)
            } header: {
                Text("Smart Tools")
            } footer: {
                Text("A black box is the safest: pixelated or blurred text can sometimes be recovered.")
                    .foregroundStyle(.secondary)
            }

            Section("Video") {
                Picker("Compress to", selection: $settings.videoCompression) {
                    ForEach(VideoCompression.allCases) { Text($0.title).tag($0) }
                }
                Picker("GIF width", selection: $settings.gifWidth) {
                    ForEach([320, 480, 640, 800], id: \.self) { Text("\($0) px").tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }
}
