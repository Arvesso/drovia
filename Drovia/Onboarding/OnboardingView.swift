import KeyboardShortcuts
import SwiftUI

struct OnboardingView: View {
    let practiceFile: URL
    let history: HistoryStore
    let onDragStart: ([URL]) -> Void
    let onDragEnd: () -> Void
    let onFinish: () -> Void

    @State private var page: Page

    enum Page: Int, CaseIterable {
        case welcome, wheels, folders, practice, done
    }

    init(
        practiceFile: URL, history: HistoryStore, startPage: Page = .welcome,
        onDragStart: @escaping ([URL]) -> Void, onDragEnd: @escaping () -> Void, onFinish: @escaping () -> Void
    ) {
        self.practiceFile = practiceFile
        self.history = history
        self.onDragStart = onDragStart
        self.onDragEnd = onDragEnd
        self.onFinish = onFinish
        _page = State(initialValue: startPage)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch page {
                case .welcome: WelcomePage()
                case .wheels: WheelsPage()
                case .folders: FoldersPage()
                case .practice: PracticePage(
                        file: practiceFile,
                        history: history,
                        onDragStart: onDragStart,
                        onDragEnd: onDragEnd
                    )
                case .done: DonePage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 48)
            .padding(.top, 40)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .id(page)

            HStack {
                if page != .welcome {
                    Button("Back") { go(-1) }
                }
                Spacer()
                if page == .done {
                    Button("Start Using Drovia", action: onFinish)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(page == .practice ? "Skip" : "Continue") { go(1) }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
            .overlay {
                HStack(spacing: 7) {
                    ForEach(Page.allCases, id: \.self) { item in
                        Circle()
                            .fill(item == page ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .frame(width: 660, height: 540)
    }

    private func go(_ step: Int) {
        guard let next = Page(rawValue: page.rawValue + step) else { return }
        withAnimation(.snappy(duration: 0.3)) { page = next }
    }
}

// MARK: - Pages

private struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
            Text("Drovia")
                .font(.system(size: 40, weight: .bold))
            Text("Your files. One gesture away.")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(
                "Drag any file, hold a modifier key, and drop it onto a wheel to convert, edit or share it — without opening another app."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 440)
            .padding(.top, 6)
        }
    }
}

private struct WheelsPage: View {
    var body: some View {
        VStack(spacing: 22) {
            Text("Four wheels, four keys")
                .font(.title.bold())
            Text("Start dragging, then press a key. The wheel shows only what fits your files.")
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], spacing: 16) {
                WheelCard(kind: .convert, symbol: "shift", examples: "PNG, WebP, PDF, MP4, M4A…")
                WheelCard(
                    kind: .tools,
                    symbol: "command",
                    examples: String(localized: "Compress, Crop, Remove BG, Text…")
                )
                WheelCard(
                    kind: .actions,
                    symbol: "control",
                    examples: String(localized: "AirDrop, Shelf, Move, Terminal…")
                )
                WheelCard(kind: .recipes, symbol: "option", examples: String(localized: "Your own chains of actions"))
            }
            Text("Press ⌃ after you start dragging: Control-click opens a menu in Finder.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WheelCard: View {
    let kind: WheelKind
    let symbol: String
    let examples: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(kind.tint)
                .frame(width: 48, height: 48)
                .background(kind.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(kind.tint.opacity(0.35)))
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title).font(.headline)
                Text(examples).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct FoldersPage: View {
    @Environment(FolderAccess.self) private var folderAccess

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Choose where Drovia works")
                .font(.title.bold())
            Text(
                "Drovia only touches files inside folders you allow — including everything inside them. macOS may ask once for Desktop, Documents and Downloads."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 460)

            if folderAccess.folders.isEmpty {
                HStack {
                    Button("Add Home Folder") { folderAccess.addHomeFolder() }
                        .buttonStyle(.borderedProminent)
                    Button("Choose Folders…") { folderAccess.chooseFolders() }
                }
                .controlSize(.large)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(folderAccess.folders) { folder in
                        Label(folder.abbreviatedPath, systemImage: folder.isHome ? "house.fill" : "folder.fill")
                    }
                }
                .padding(14)
                .frame(maxWidth: 360, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                Button("Add More…") { folderAccess.chooseFolders() }
                    .buttonStyle(.link)
            }
        }
    }
}

private struct PracticePage: View {
    let file: URL
    let history: HistoryStore
    let onDragStart: ([URL]) -> Void
    let onDragEnd: () -> Void

    @State private var startCount: Int?
    @State private var thumbnail: NSImage?

    private var succeeded: Bool {
        guard let startCount else { return false }
        return history.entries.count > startCount
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(succeeded ? "Nicely done!" : "Try it")
                .font(.title.bold())
            Text(succeeded
                ? "That's all there is to it. The result is saved next to the sample; click the message to see it."
                : "Drag the picture a little, hold ⇧ and drop it on JPEG. Or hold ⌘ and try Remove BG.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)

            ZStack {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        RoundedRectangle(cornerRadius: 12).fill(.quaternary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                .allowsHitTesting(false)

                FileDragSource(urls: { [file] }, onBegin: onDragStart, onEnd: { _ in onDragEnd() })
            }
            .frame(width: 240, height: 160)
            .overlay(alignment: .topTrailing) {
                if succeeded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.white, .green)
                        .offset(x: 14, y: -14)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35, bounce: 0.4), value: succeeded)

            Text("Tip: the sample isn't in an allowed folder — files you drag out of Drovia's own windows always work.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .onAppear { startCount = startCount ?? history.entries.count }
        .task { thumbnail = await Thumbnails.image(for: DragContent(fileURLs: [file]), side: 240) }
    }
}

private struct DonePage: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        VStack(spacing: 20) {
            Text("You're all set")
                .font(.title.bold())
            VStack(alignment: .leading, spacing: 14) {
                let shortcut = KeyboardShortcuts.getShortcut(for: .showWheel)?.description ?? "⌃⌥D"
                Tip(
                    symbol: "keyboard",
                    text: "Select files in Finder and press \(shortcut) to open the wheel without dragging."
                )
                Tip(
                    symbol: "menubar.arrow.up.rectangle",
                    text: "Drovia lives in the menu bar: undo, recent results and the shelf are there."
                )
                Tip(symbol: "wand.and.stars", text: "Make your own recipes and reorder wheels in Settings.")
                Tip(
                    symbol: "arrow.uturn.backward.circle",
                    text: "Every change can be undone; originals are never overwritten."
                )
            }
            .frame(maxWidth: 440)
            Toggle("Open Drovia at login", isOn: $settings.launchAtLogin)
                .toggleStyle(.switch)
                .padding(.top, 8)
        }
    }
}

private struct Tip: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(.tint)
                .frame(width: 26)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
