import SwiftUI

struct EditorView: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            canvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .underPageBackgroundColor))
            Divider()
            bottomBar
                .padding(.horizontal, 14)
                .frame(height: 56)
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    // MARK: - Top

    private var topBar: some View {
        HStack(spacing: 12) {
            Picker("Mode", selection: $model.mode) {
                ForEach(EditorMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Spacer()

            if model.files.count > 1 {
                Text("\(model.index + 1) of \(model.files.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ControlGroup {
                // While typing, ⌘Z belongs to the text field.
                Button("Undo", systemImage: "arrow.uturn.backward") { model.undo() }
                    .keyboardShortcut("z")
                    .disabled(!model.canUndo || model.textEntry != nil)
                Button("Redo", systemImage: "arrow.uturn.forward") { model.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!model.canRedo || model.textEntry != nil)
            }
            .fixedSize()

            // Esc while typing drops the text being typed, not every edit made to the image.
            Button("Cancel") {
                if model.textEntry != nil {
                    model.textEntry = nil
                } else {
                    model.finish()
                }
            }
            .keyboardShortcut(.cancelAction)
            .disabled(model.isSaving)
            if model.hasMoreFiles {
                Button("Skip") { model.skip() }
                    .disabled(model.isSaving)
                if model.mode == .background {
                    Button("Apply to All") { Task { await model.saveAllWithBackground() } }
                        .help("Save this image, then add the same background to the rest")
                }
            }
            Button(model.hasMoreFiles ? LocalizedStringKey("Save & Next") : "Save") { Task { await model.save() } }
                .keyboardShortcut("s")
                .buttonStyle(.borderedProminent)
                .disabled(model.isSaving || model.preview == nil)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Canvas

    @ViewBuilder
    private var canvas: some View {
        if let error = model.loadError {
            ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
        } else {
            switch model.mode {
            case .crop: CropCanvas(model: model)
            case .annotate: AnnotationCanvas(model: model)
            case .background: BackgroundPreview(model: model)
            }
        }
    }

    // MARK: - Bottom

    @ViewBuilder
    private var bottomBar: some View {
        switch model.mode {
        case .crop: cropBar
        case .annotate: annotateBar
        case .background: backgroundBar
        }
    }

    private var cropBar: some View {
        HStack {
            Picker("Aspect Ratio", selection: $model.cropAspect) {
                ForEach(CropAspect.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Spacer()
            Button("Reset", systemImage: "arrow.counterclockwise") { model.resetCrop() }
        }
    }

    private var annotateBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 2) {
                ForEach(AnnotationTool.allCases) { tool in
                    Button {
                        model.tool = tool
                    } label: {
                        Image(systemName: tool.symbol)
                            .frame(width: 30, height: 26)
                            .background(
                                model.tool == tool ? Color.accentColor.opacity(0.25) : .clear,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(tool.title)
                    .accessibilityLabel(tool.title)
                    .accessibilityAddTraits(model.tool == tool ? .isSelected : [])
                }
            }

            Divider().frame(height: 24)

            HStack(spacing: 6) {
                ForEach(RGBA.palette, id: \.self) { color in
                    Button {
                        model.color = color
                    } label: {
                        Circle()
                            .fill(Color(cgColor: color.cgColor))
                            .overlay(Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1))
                            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2.5).padding(-4)
                                .opacity(model.color == color ? 1 : 0))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Color"))
                    .accessibilityAddTraits(model.color == color ? .isSelected : [])
                }
            }

            Divider().frame(height: 24)

            Picker("Size", selection: $model.strokeSize) {
                Text("S").tag(StrokeSize.small)
                Text("M").tag(StrokeSize.medium)
                Text("L").tag(StrokeSize.large)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Spacer()
        }
    }

    private var backgroundBar: some View {
        HStack(spacing: 14) {
            Toggle("Background", isOn: $model.usesBackground)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()

            HStack(spacing: 6) {
                ForEach(BackgroundFill.presets, id: \.self) { fill in
                    Button {
                        model.setBackground { $0.fill = fill }
                    } label: {
                        FillSwatch(fill: fill, isSelected: model.background.fill == fill)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(fill == .none ? Text("No background") : Text("Background color"))
                    .accessibilityAddTraits(model.background.fill == fill ? .isSelected : [])
                }
            }

            Divider().frame(height: 24)
            slider("Padding", value: \.padding, range: 0 ... 0.3)
            slider("Corners", value: \.cornerRadius, range: 0 ... 0.1)
            slider("Shadow", value: \.shadow, range: 0 ... 1)

            Picker("Aspect Ratio", selection: Binding(
                get: { model.background.aspect },
                set: { aspect in model.setBackground { $0.aspect = aspect } }
            )) {
                ForEach(BackgroundAspect.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        }
        .disabled(!model.usesBackground)
    }

    private func slider(
        _ title: LocalizedStringKey,
        value: WritableKeyPath<BackgroundStyle, Double>,
        range: ClosedRange<Double>
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: { model.background[keyPath: value] },
                    set: { model.background[keyPath: value] = $0 }
                ),
                in: range
            ) { isEditing in
                if isEditing {
                    model.recordUndo()
                }
            }
            .frame(width: 80)
            .controlSize(.small)
        }
    }
}

private struct FillSwatch: View {
    let fill: BackgroundFill
    let isSelected: Bool

    var body: some View {
        ZStack {
            switch fill {
            case .none:
                Circle().fill(.background)
                Image(systemName: "line.diagonal")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.red)
            case let .solid(color):
                Circle().fill(Color(cgColor: color.cgColor))
            case let .gradient(index):
                let colors = BackgroundFill.gradients[index]
                Circle().fill(LinearGradient(
                    colors: [Color(cgColor: colors.0.cgColor), Color(cgColor: colors.1.cgColor)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            }
        }
        .overlay(Circle().strokeBorder(.primary.opacity(0.2), lineWidth: 1))
        .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2.5).padding(-4).opacity(isSelected ? 1 : 0))
        .frame(width: 20, height: 20)
    }
}
