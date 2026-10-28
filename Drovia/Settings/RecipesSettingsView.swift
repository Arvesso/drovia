import SwiftUI

struct RecipesSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var selection: Recipe.ID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(settings.recipes) { recipe in
                        Label(recipe.name, systemImage: recipe.symbol)
                            .tag(recipe.id)
                    }
                    .onMove { settings.recipes.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.sidebar)

                HStack(spacing: 0) {
                    Button("Add Recipe", systemImage: "plus") {
                        let recipe = Recipe(name: String(localized: "New Recipe"), symbol: "wand.and.stars", steps: [])
                        settings.recipes.append(recipe)
                        selection = recipe.id
                    }
                    Button("Remove Recipe", systemImage: "minus") {
                        settings.recipes.removeAll { $0.id == selection }
                        selection = settings.recipes.first?.id
                    }
                    .disabled(selection == nil)
                    Spacer()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(width: 180)

            Divider()

            if let index = settings.recipes.firstIndex(where: { $0.id == selection }) {
                RecipeEditor(recipe: Binding(
                    get: { settings.recipes[index] },
                    set: { settings.recipes[index] = $0 }
                ))
                .id(settings.recipes[index].id)
            } else {
                ContentUnavailableView(
                    "No Recipe Selected",
                    systemImage: "wand.and.stars",
                    description: Text("Recipes chain actions together. Drag files and hold ⌥ to run one.")
                )
            }
        }
        .onAppear { selection = selection ?? settings.recipes.first?.id }
    }
}

private struct RecipeEditor: View {
    @Environment(SettingsStore.self) private var settings
    @Binding var recipe: Recipe
    @State private var shortcutNames: [String] = []

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $recipe.name)
                Picker("Icon", selection: $recipe.symbol) {
                    ForEach(Recipe.symbols, id: \.self) { symbol in
                        Image(systemName: symbol).tag(symbol)
                    }
                }
            }

            Section {
                if recipe.steps.isEmpty {
                    Text("Add steps; each one works on the files the previous step made.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                    StepRow(index: index, step: $recipe.steps[index]) {
                        recipe.steps.remove(at: index)
                    }
                    .tag(step)
                }
                .onMove { recipe.steps.move(fromOffsets: $0, toOffset: $1) }

                addStepMenu
            } header: {
                Text("Steps")
            } footer: {
                let action = RecipeAction(recipe: recipe)
                let kinds = FileKind.allCases.filter { kind in
                    kind.sampleTypes.contains { action.supports([$0]) }
                }
                if let step = action.stepBeforeResults {
                    // Says why the recipe doesn't show up on the wheel.
                    Text(RecipeError.stepBeforeResults(step.title).localizedDescription)
                        .foregroundStyle(.orange)
                } else {
                    Text(kinds.isEmpty
                        ? String(localized: "No file type fits every step yet.")
                        : String(localized: "Works with: \(kinds.map(\.title).formatted(.list(type: .and)))"))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task { shortcutNames = await RecipeScripts.shortcutNames() }
    }

    private var addStepMenu: some View {
        Menu {
            ForEach(WheelKind.allCases.filter { $0 != .recipes }, id: \.self) { wheel in
                Menu(wheel.title) {
                    ForEach(ActionRegistry.sectors(for: wheel, layout: WheelLayout())) { sector in
                        Button {
                            recipe.steps.append(.action(sectorID: sector.id))
                        } label: {
                            if let symbol = sector.symbol {
                                Label(sector.title, systemImage: symbol)
                            } else {
                                Text(sector.title)
                            }
                        }
                    }
                }
            }
            Divider()
            Menu("Run Shortcut") {
                if shortcutNames.isEmpty {
                    Text("No shortcuts found")
                }
                ForEach(shortcutNames, id: \.self) { name in
                    Button(name) { recipe.steps.append(.shortcut(name: name)) }
                }
            }
            Button("Run Shell Script") {
                let template = "# Files are in \"$@\"\nfor file in \"$@\"; do\n  echo \"$file\"\ndone"
                settings.scriptApprovals.approve(template)
                recipe.steps.append(.script(template))
            }
        } label: {
            Label("Add Step", systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

private struct StepRow: View {
    @Environment(SettingsStore.self) private var settings
    let index: Int
    @Binding var step: Recipe.Step
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("\(index + 1)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Group {
                    if let symbol = step.symbol {
                        Image(systemName: symbol)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .foregroundStyle(step.sectorWheel?.tint ?? .accentColor)
                .frame(width: 20)
                VStack(alignment: .leading, spacing: 0) {
                    Text(step.title)
                    if let wheel = step.sectorWheel {
                        Text(wheel.title).font(.caption).foregroundStyle(.secondary)
                    } else if case .shortcut = step {
                        Text("Shortcut").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Remove", systemImage: "minus.circle.fill", action: onDelete)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
            if case let .script(source) = step {
                // Typed here, so it's the user's own: approved before the change is saved.
                TextEditor(text: Binding(get: { source }, set: { text in
                    settings.scriptApprovals.approve(text)
                    step = .script(text)
                }))
                .font(.system(size: 11, design: .monospaced))
                .frame(height: 80)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}
