import AVFoundation
import UniformTypeIdentifiers

/// Video exports are heavy; two at a time keeps the Mac responsive.
private let mediaConcurrency = 2

private func allVideos(_ types: [UTType]) -> Bool {
    !types.isEmpty && types.allSatisfy(MediaEngine.isVideo)
}

private func videoFileType(for file: URL) -> (AVFileType, String) {
    file.pathExtension.lowercased() == "mov" ? (.mov, "mov") : (.mp4, "mp4")
}

// MARK: - Convert

struct VideoConvertAction: DroviaAction {
    enum Target: String, CaseIterable {
        case mp4, mov, gif
    }

    let target: Target

    var id: String {
        "convert.video.\(target.rawValue)"
    }

    var wheel: WheelKind {
        .convert
    }

    var title: String {
        target.rawValue.uppercased()
    }

    var progressTitle: String {
        String(localized: "Converting to \(title)")
    }

    var producesFiles: Bool {
        true
    }

    func supports(_ types: [UTType]) -> Bool {
        guard allVideos(types) else { return false }
        switch target {
        case .mp4: return types.contains { !$0.conforms(to: .mpeg4Movie) }
        case .mov: return types.contains { !$0.conforms(to: .quickTimeMovie) }
        case .gif: return true
        }
    }

    func perform(_ files: [URL], context: ActionContext) async throws -> ActionResult {
        let planner = context.planner
        let target = target
        let gifWidth = context.settings.gifWidth
        return await context.processEach(files, concurrency: mediaConcurrency) { source, progress in
            let destination = await planner.destination(for: source, action: nil, fileExtension: target.rawValue)
            switch target {
            case .mp4:
                try await MediaEngine.convert(source, to: .mp4, destination: destination, progress: progress)
            case .mov:
                try await MediaEngine.convert(source, to: .mov, destination: destination, progress: progress)
            case .gif:
                try await MediaEngine.makeGIF(source, destination: destination, width: gifWidth, progress: progress)
            }
            return destination
        }
    }
}

/// Audio from audio files, or the soundtrack of videos.
struct AudioConvertAction: DroviaAction {
    let format: AudioFormat

    var id: String {
        "convert.audio.\(format.rawValue)"
    }

    var wheel: WheelKind {
        .convert
    }

    var title: String {
        format.rawValue.uppercased()
    }

    var progressTitle: String {
        String(localized: "Converting to \(title)")
    }

    var producesFiles: Bool {
        true
    }

    func supports(_ types: [UTType]) -> Bool {
        !types.isEmpty && types.allSatisfy { MediaEngine.isAudio($0) || MediaEngine.isVideo($0) }
            && types.contains { !$0.conforms(to: format.utType) }
    }

    func perform(_ files: [URL], context: ActionContext) async throws -> ActionResult {
        let planner = context.planner
        let format = format
        return await context.processEach(files, concurrency: mediaConcurrency) { source, progress in
            let destination = await planner.destination(for: source, action: nil, fileExtension: format.rawValue)
            try await MediaEngine.convertAudio(source, to: format, destination: destination, progress: progress)
            return destination
        }
    }
}

// MARK: - Tools

struct VideoToolAction: DroviaAction {
    enum Kind: String {
        case compress, mute, rotate
    }

    let kind: Kind
    let wheel = WheelKind.tools
    let producesFiles = true

    var id: String {
        "tools.\(kind.rawValue).video"
    }

    var title: String {
        switch kind {
        case .compress: String(localized: "Compress")
        case .mute: String(localized: "Mute")
        case .rotate: String(localized: "Rotate")
        }
    }

    var symbol: String? {
        switch kind {
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .mute: "speaker.slash"
        case .rotate: "rotate.right"
        }
    }

    var progressTitle: String {
        switch kind {
        case .compress: String(localized: "Compressing")
        case .mute: String(localized: "Removing sound")
        case .rotate: String(localized: "Rotating")
        }
    }

    func supports(_ types: [UTType]) -> Bool {
        allVideos(types)
    }

    func perform(_ files: [URL], context: ActionContext) async throws -> ActionResult {
        let planner = context.planner
        let kind = kind
        let compression = context.settings.videoCompression
        var result = await context.processEach(files, concurrency: mediaConcurrency) { source, progress in
            switch kind {
            case .compress:
                let destination = await planner.destination(for: source, action: "compressed", fileExtension: "mp4")
                try await MediaEngine.compress(source, using: compression, destination: destination, progress: progress)
                guard let before = source.fileSize, let after = destination.fileSize, after < before * 97 / 100 else {
                    try? FileManager.default.removeItem(at: destination)
                    return nil
                }
                return destination
            case .mute:
                let (fileType, ext) = videoFileType(for: source)
                let destination = await planner.destination(for: source, action: "muted", fileExtension: ext)
                try await MediaEngine.removeAudio(
                    source,
                    destination: destination,
                    fileType: fileType,
                    progress: progress
                )
                return destination
            case .rotate:
                let (fileType, ext) = videoFileType(for: source)
                let destination = await planner.destination(for: source, action: "rotated", fileExtension: ext)
                try await MediaEngine.rotateClockwise(
                    source,
                    destination: destination,
                    fileType: fileType,
                    progress: progress
                )
                return destination
            }
        }
        if kind == .compress, result.outputs.isEmpty, result.failures.isEmpty {
            result.message = String(localized: "Already as small as it gets")
        }
        return result
    }
}
