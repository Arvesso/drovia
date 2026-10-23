import Foundation
import Observation
import os
import ServiceManagement

enum WheelSize: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: Self {
        self
    }

    var scale: CGFloat {
        switch self {
        case .small: 0.85
        case .medium: 1
        case .large: 1.15
        }
    }

    var title: String {
        switch self {
        case .small: String(localized: "Small")
        case .medium: String(localized: "Medium")
        case .large: String(localized: "Large")
        }
    }
}

enum OutputLocation: String, CaseIterable, Identifiable {
    case nextToOriginal, folder, ask

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .nextToOriginal: String(localized: "Next to the original")
        case .folder: String(localized: "In a folder")
        case .ask: String(localized: "Ask every time")
        }
    }
}

enum MetadataRemoval: String, CaseIterable, Identifiable, Sendable {
    case all, location

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .all: String(localized: "All metadata")
        case .location: String(localized: "Location only")
        }
    }
}

/// App settings persisted in UserDefaults.
@MainActor
@Observable
final class SettingsStore {
    // MARK: General

    var launchAtLogin: Bool {
        didSet { updateLaunchAtLogin() }
    }

    var wheelSize: WheelSize {
        didSet { defaults.set(wheelSize.rawValue, forKey: Keys.wheelSize) }
    }

    /// Seconds a modifier must be held before the wheel appears.
    var activationDelay: Double {
        didSet { defaults.set(activationDelay, forKey: Keys.activationDelay) }
    }

    var hidesWheelOnModifierRelease: Bool {
        didSet { defaults.set(hidesWheelOnModifierRelease, forKey: Keys.hidesWheelOnModifierRelease) }
    }

    // MARK: Output

    var outputLocation: OutputLocation {
        didSet { defaults.set(outputLocation.rawValue, forKey: Keys.outputLocation) }
    }

    var outputFolderPath: String? {
        didSet { defaults.set(outputFolderPath, forKey: Keys.outputFolderPath) }
    }

    var fileNameTemplate: String {
        didSet { defaults.set(fileNameTemplate, forKey: Keys.fileNameTemplate) }
    }

    var trashesOriginals: Bool {
        didSet { defaults.set(trashesOriginals, forKey: Keys.trashesOriginals) }
    }

    var addsResultsToShelf: Bool {
        didSet { defaults.set(addsResultsToShelf, forKey: Keys.addsResultsToShelf) }
    }

    // MARK: Images

    var imageQuality: Double {
        didSet { defaults.set(imageQuality, forKey: Keys.imageQuality) }
    }

    var keepsMetadataOnConvert: Bool {
        didSet { defaults.set(keepsMetadataOnConvert, forKey: Keys.keepsMetadataOnConvert) }
    }

    /// Longest side when compressing, 0 keeps the original size.
    var compressMaxDimension: Int {
        didSet { defaults.set(compressMaxDimension, forKey: Keys.compressMaxDimension) }
    }

    var compressRemovesMetadata: Bool {
        didSet { defaults.set(compressRemovesMetadata, forKey: Keys.compressRemovesMetadata) }
    }

    var resizePreset: ResizePreset {
        didSet { defaults.set(resizePreset.rawValue, forKey: Keys.resizePreset) }
    }

    var metadataRemoval: MetadataRemoval {
        didSet { defaults.set(metadataRemoval.rawValue, forKey: Keys.metadataRemoval) }
    }

    var removeBackgroundCrops: Bool {
        didSet { defaults.set(removeBackgroundCrops, forKey: Keys.removeBackgroundCrops) }
    }

    var redactionStyle: RedactionStyle {
        didSet { defaults.set(redactionStyle.rawValue, forKey: Keys.redactionStyle) }
    }

    var redactsFaces: Bool {
        didSet { defaults.set(redactsFaces, forKey: Keys.redactsFaces) }
    }

    var redactsPersonalText: Bool {
        didSet { defaults.set(redactsPersonalText, forKey: Keys.redactsPersonalText) }
    }

    var redactsCodes: Bool {
        didSet { defaults.set(redactsCodes, forKey: Keys.redactsCodes) }
    }

    var redactionTargets: RedactionTargets {
        var targets: RedactionTargets = []
        if redactsFaces {
            targets.insert(.faces)
        }
        if redactsPersonalText {
            targets.insert(.personalText)
        }
        if redactsCodes {
            targets.insert(.codes)
        }
        return targets
    }

    // MARK: Video

    var videoCompression: VideoCompression {
        didSet { defaults.set(videoCompression.rawValue, forKey: Keys.videoCompression) }
    }

    /// Width of GIFs made from videos, in pixels.
    var gifWidth: Int {
        didSet { defaults.set(gifWidth, forKey: Keys.gifWidth) }
    }

    // MARK: Actions

    var terminalApp: TerminalApp {
        didSet { defaults.set(terminalApp.rawValue, forKey: Keys.terminalApp) }
    }

    var copyPathFormat: CopyPathFormat {
        didSet { defaults.set(copyPathFormat.rawValue, forKey: Keys.copyPathFormat) }
    }

    var favoriteFolders: [String] {
        didSet { defaults.set(favoriteFolders, forKey: Keys.favoriteFolders) }
    }

    private(set) var recentMoveFolders: [String] {
        didSet { defaults.set(recentMoveFolders, forKey: Keys.recentMoveFolders) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        launchAtLogin = SMAppService.mainApp.status == .enabled
        wheelSize = defaults.enumValue(forKey: Keys.wheelSize) ?? .medium
        activationDelay = defaults.object(forKey: Keys.activationDelay) as? Double ?? 0
        hidesWheelOnModifierRelease = defaults.object(forKey: Keys.hidesWheelOnModifierRelease) as? Bool ?? true
        outputLocation = defaults.enumValue(forKey: Keys.outputLocation) ?? .nextToOriginal
        outputFolderPath = defaults.string(forKey: Keys.outputFolderPath)
        fileNameTemplate = defaults.string(forKey: Keys.fileNameTemplate) ?? NamingTemplate.defaultTemplate
        trashesOriginals = defaults.bool(forKey: Keys.trashesOriginals)
        addsResultsToShelf = defaults.bool(forKey: Keys.addsResultsToShelf)
        imageQuality = defaults.object(forKey: Keys.imageQuality) as? Double ?? 0.8
        keepsMetadataOnConvert = defaults.object(forKey: Keys.keepsMetadataOnConvert) as? Bool ?? true
        compressMaxDimension = defaults.integer(forKey: Keys.compressMaxDimension)
        compressRemovesMetadata = defaults.object(forKey: Keys.compressRemovesMetadata) as? Bool ?? true
        resizePreset = defaults.enumValue(forKey: Keys.resizePreset) ?? .half
        metadataRemoval = defaults.enumValue(forKey: Keys.metadataRemoval) ?? .all
        removeBackgroundCrops = defaults.bool(forKey: Keys.removeBackgroundCrops)
        redactionStyle = defaults.enumValue(forKey: Keys.redactionStyle) ?? .blackBox
        redactsFaces = defaults.object(forKey: Keys.redactsFaces) as? Bool ?? true
        redactsPersonalText = defaults.object(forKey: Keys.redactsPersonalText) as? Bool ?? true
        redactsCodes = defaults.object(forKey: Keys.redactsCodes) as? Bool ?? true
        videoCompression = defaults.enumValue(forKey: Keys.videoCompression) ?? .hevc1080
        gifWidth = defaults.object(forKey: Keys.gifWidth) as? Int ?? 480
        terminalApp = defaults.enumValue(forKey: Keys.terminalApp) ?? .terminal
        copyPathFormat = defaults.enumValue(forKey: Keys.copyPathFormat) ?? .posix
        favoriteFolders = defaults.stringArray(forKey: Keys.favoriteFolders) ?? []
        recentMoveFolders = defaults.stringArray(forKey: Keys.recentMoveFolders) ?? []
    }

    func noteMoveDestination(_ path: String) {
        recentMoveFolders = Array(([path] + recentMoveFolders.filter { $0 != path }).prefix(5))
    }

    private func updateLaunchAtLogin() {
        let service = SMAppService.mainApp
        guard launchAtLogin != (service.status == .enabled) else { return }
        do {
            if launchAtLogin {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            Logger.wheel.error("Launch at login failed: \(error.localizedDescription)")
            launchAtLogin = service.status == .enabled
        }
    }

    private enum Keys {
        static let wheelSize = "wheelSize"
        static let activationDelay = "activationDelay"
        static let hidesWheelOnModifierRelease = "hidesWheelOnModifierRelease"
        static let outputLocation = "outputLocation"
        static let outputFolderPath = "outputFolderPath"
        static let fileNameTemplate = "fileNameTemplate"
        static let trashesOriginals = "trashesOriginals"
        static let addsResultsToShelf = "addsResultsToShelf"
        static let imageQuality = "imageQuality"
        static let keepsMetadataOnConvert = "keepsMetadataOnConvert"
        static let compressMaxDimension = "compressMaxDimension"
        static let compressRemovesMetadata = "compressRemovesMetadata"
        static let resizePreset = "resizePreset"
        static let metadataRemoval = "metadataRemoval"
        static let removeBackgroundCrops = "removeBackgroundCrops"
        static let redactionStyle = "redactionStyle"
        static let redactsFaces = "redactsFaces"
        static let redactsPersonalText = "redactsPersonalText"
        static let redactsCodes = "redactsCodes"
        static let videoCompression = "videoCompression"
        static let gifWidth = "gifWidth"
        static let terminalApp = "terminalApp"
        static let copyPathFormat = "copyPathFormat"
        static let favoriteFolders = "favoriteFolders"
        static let recentMoveFolders = "recentMoveFolders"
    }
}

private extension UserDefaults {
    func enumValue<T: RawRepresentable>(forKey key: String) -> T? where T.RawValue == String {
        string(forKey: key).flatMap(T.init)
    }
}
