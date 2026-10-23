import SwiftUI

struct WheelsSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var wheel = WheelKind.tools

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Wheel", selection: $wheel) {
                // Recipes are arranged in their own tab.
                ForEach(WheelKind.allCases.filter { $0 != .recipes }, id: \.self) { kind in
                    Text("\(kind.title) (\(kind.modifierSymbol))").tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            List {
                ForEach(ActionRegistry.sectors(for: wheel, layout: settings.wheelLayout)) { sector in
                    SectorRow(sector: sector, isVisible: isVisible(sector))
                }
                .onMove(perform: move)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            HStack {
                Text("Drag to reorder. Only sectors that fit the dragged files appear on the wheel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Restore Defaults") {
                    settings.wheelLayout.order[wheel.rawValue] = nil
                    let ids = Set(ActionRegistry.sectors(for: wheel, layout: WheelLayout()).map(\.id))
                    settings.wheelLayout.hidden.subtract(ids)
                }
            }
        }
        .padding()
    }

    private func isVisible(_ sector: WheelSector) -> Binding<Bool> {
        Binding(
            get: { !settings.wheelLayout.hidden.contains(sector.id) },
            set: { visible in
                if visible {
                    settings.wheelLayout.hidden.remove(sector.id)
                } else {
                    settings.wheelLayout.hidden.insert(sector.id)
                }
            }
        )
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ids = ActionRegistry.sectors(for: wheel, layout: settings.wheelLayout).map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        settings.wheelLayout.order[wheel.rawValue] = ids
    }
}

private struct SectorRow: View {
    let sector: WheelSector
    let isVisible: Binding<Bool>

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let symbol = sector.symbol {
                    Image(systemName: symbol)
                } else {
                    Text(sector.title)
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.5)
                }
            }
            .frame(width: 26, height: 22)
            .foregroundStyle(isVisible.wrappedValue ? Color.accentColor : .secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(sector.title)
                Text(sector.kinds.map(\.title).formatted(.list(type: .and)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .opacity(isVisible.wrappedValue ? 1 : 0.5)

            Spacer()
            Toggle("Show", isOn: isVisible)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .padding(.vertical, 2)
    }
}
