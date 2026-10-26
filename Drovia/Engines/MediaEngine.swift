import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum MediaEngineError: LocalizedError {
    case unsupported(URL)
    case noAudio(URL)
    case noVideo(URL)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case let .unsupported(url): String(localized: "Can't convert \(url.lastPathComponent)")
        case let .noAudio(url): String(localized: "\(url.lastPathComponent) has no sound")
        case let .noVideo(url): String(localized: "\(url.lastPathComponent) has no video")
        case let .exportFailed(reason): reason
        }
    }
}

enum VideoFormat: String, CaseIterable, Sendable {
    case mp4, mov

    var fileType: AVFileType {
        self == .mp4 ? .mp4 : .mov
    }
}

enum AudioFormat: String, CaseIterable, Sendable {
    case m4a, wav, aiff

    var fileType: AVFileType {
        switch self {
        case .m4a: .m4a
        case .wav: .wav
        case .aiff: .aiff
        }
    }

    var utType: UTType {
        switch self {
        case .m4a: .mpeg4Audio
        case .wav: .wav
        case .aiff: .aiff
        }
    }
}

enum VideoCompression: String, CaseIterable, Identifiable, Sendable {
    case hevc1080, h2641080, h264720

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .hevc1080: String(localized: "HEVC, up to 1080p")
        case .h2641080: String(localized: "H.264, up to 1080p")
        case .h264720: String(localized: "H.264, up to 720p")
        }
    }

    var preset: String {
        switch self {
        case .hevc1080: AVAssetExportPresetHEVC1920x1080
        case .h2641080: AVAssetExportPreset1920x1080
        case .h264720: AVAssetExportPreset1280x720
        }
    }
}

/// Video and audio processing with AVFoundation.
enum MediaEngine {
    typealias Progress = @Sendable (Double) -> Void

    // MARK: - Types

    /// UTIs AVFoundation can open.
    private static let playableTypes: [UTType] = AVURLAsset.audiovisualTypes().compactMap { UTType($0.rawValue) }

    static func isVideo(_ type: UTType) -> Bool {
        type.conforms(to: .movie) && playableTypes.contains { type.conforms(to: $0) }
    }

    static func isAudio(_ type: UTType) -> Bool {
        type.conforms(to: .audio) && playableTypes.contains { type.conforms(to: $0) }
    }

    // MARK: - Video

    /// Rewraps the streams without re-encoding when the container allows it, otherwise re-encodes at high quality.
    static func convert(
        _ source: URL,
        to format: VideoFormat,
        destination: URL,
        progress: @escaping Progress
    ) async throws {
        let asset = AVURLAsset(url: source)
        guard try await !asset.loadTracks(withMediaType: .video).isEmpty else { throw MediaEngineError.noVideo(source) }
        let passthrough = await AVAssetExportSession.compatibility(
            ofExportPreset: AVAssetExportPresetPassthrough, with: asset, outputFileType: format.fileType
        )
        let preset = passthrough ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality
        try await export(asset, preset: preset, to: destination, fileType: format.fileType, progress: progress)
    }

    static func compress(
        _ source: URL,
        using compression: VideoCompression,
        destination: URL,
        progress: @escaping Progress
    ) async throws {
        let asset = AVURLAsset(url: source)
        try await export(asset, preset: compression.preset, to: destination, fileType: .mp4, progress: progress)
    }

    /// Drops all audio tracks without re-encoding the video.
    static func removeAudio(
        _ source: URL,
        destination: URL,
        fileType: AVFileType,
        progress: @escaping Progress
    ) async throws {
        let asset = AVURLAsset(url: source)
        let composition = AVMutableComposition()
        let duration = try await asset.load(.duration)
        for track in try await asset.loadTracks(withMediaType: .video) {
            guard let copy = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
            else { continue }
            try copy.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
            copy.preferredTransform = try await track.load(.preferredTransform)
        }
        guard !composition.tracks.isEmpty else { throw MediaEngineError.noVideo(source) }
        try await export(
            composition,
            preset: AVAssetExportPresetPassthrough,
            to: destination,
            fileType: fileType,
            progress: progress
        )
    }

    /// Rotates 90° clockwise by changing the track's display transform — no re-encoding.
    static func rotateClockwise(
        _ source: URL,
        destination: URL,
        fileType: AVFileType,
        progress: @escaping Progress
    ) async throws {
        let asset = AVURLAsset(url: source)
        let composition = AVMutableComposition()
        let duration = try await asset.load(.duration)
        let range = CMTimeRange(start: .zero, duration: duration)
        for track in try await asset.loadTracks(withMediaType: .video) {
            guard let copy = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
            else { continue }
            try copy.insertTimeRange(range, of: track, at: .zero)
            let (transform, size) = try await track.load(.preferredTransform, .naturalSize)
            copy.preferredTransform = rotatedClockwise(transform, naturalSize: size)
        }
        guard !composition.tracks.isEmpty else { throw MediaEngineError.noVideo(source) }
        for track in try await asset.loadTracks(withMediaType: .audio) {
            let copy = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
            try copy?.insertTimeRange(range, of: track, at: .zero)
        }
        try await export(
            composition,
            preset: AVAssetExportPresetPassthrough,
            to: destination,
            fileType: fileType,
            progress: progress
        )
    }

    /// `transform` followed by a 90° clockwise turn, shifted so the picture stays at the origin.
    static func rotatedClockwise(_ transform: CGAffineTransform, naturalSize: CGSize) -> CGAffineTransform {
        // In video (y-down) coordinates a clockwise turn maps (x, y) to (-y, x).
        let rotated = transform.concatenating(CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0))
        let bounds = CGRect(origin: .zero, size: naturalSize).applying(rotated)
        return rotated.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
    }

    /// An animated GIF of up to `maxDuration` seconds, `width` pixels wide, at `fps` frames per second.
    static func makeGIF(
        _ source: URL, destination: URL, width: Int, fps: Double = 12, maxDuration: Double = 30,
        progress: @escaping Progress
    ) async throws {
        let asset = AVURLAsset(url: source)
        guard try await !asset.loadTracks(withMediaType: .video).isEmpty else { throw MediaEngineError.noVideo(source) }
        // Streams and broken files have no usable duration (NaN would crash the frame count below).
        let length = try await asset.load(.duration)
        guard length.isNumeric, length.seconds > 0 else { throw MediaEngineError.unsupported(source) }
        let duration = min(length.seconds, maxDuration)
        let frameCount = max(1, Int(duration * fps))
        let times = (0 ..< frameCount).map { CMTime(seconds: Double($0) / fps, preferredTimescale: 600) }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: width, height: 0)
        let tolerance = CMTime(seconds: 0.5 / fps, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        guard let gif = CGImageDestinationCreateWithURL(
            destination as CFURL,
            UTType.gif.identifier as CFString,
            frameCount,
            nil
        )
        else { throw ImageEngineError.cannotWrite(.gif) }
        CGImageDestinationSetProperties(gif, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps],
        ] as CFDictionary

        var written = 0
        for await result in generator.images(for: times) {
            guard let image = try? result.image else { continue }
            CGImageDestinationAddImage(gif, image, frameProperties)
            written += 1
            progress(Double(written) / Double(frameCount))
        }
        guard written > 0, CGImageDestinationFinalize(gif) else { throw ImageEngineError.cannotWrite(.gif) }
    }

    // MARK: - Audio

    /// Audio from an audio or video file. AAC goes through an export preset; WAV and AIFF are decoded to PCM.
    static func convertAudio(
        _ source: URL,
        to format: AudioFormat,
        destination: URL,
        progress: @escaping Progress
    ) async throws {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw MediaEngineError.noAudio(source)
        }
        if format == .m4a {
            try await export(
                asset,
                preset: AVAssetExportPresetAppleM4A,
                to: destination,
                fileType: .m4a,
                progress: progress
            )
        } else {
            try await writePCM(from: asset, track: track, to: destination, format: format, progress: progress)
        }
    }

    private static func writePCM(
        from asset: AVAsset, track: AVAssetTrack, to destination: URL, format: AudioFormat, progress: @escaping Progress
    ) async throws {
        let descriptions = try await track.load(.formatDescriptions)
        let basic = descriptions.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
        let sampleRate = basic?.mSampleRate ?? 44100
        let channels = min(Int(basic?.mChannelsPerFrame ?? 2), 2)
        let duration = try await asset.load(.duration).seconds

        let pcm: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: format == .aiff,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: pcm)
        reader.add(output)
        let writer = try AVAssetWriter(outputURL: destination, fileType: format.fileType)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: pcm)
        input.expectsMediaDataInRealTime = false
        writer.add(input)

        guard reader.startReading(), writer.startWriting() else {
            throw MediaEngineError.exportFailed(reader.error?.localizedDescription ?? writer.error?.localizedDescription
                ?? String(localized: "Can't convert \(destination.lastPathComponent)"))
        }
        writer.startSession(atSourceTime: .zero)
        while let buffer = output.copyNextSampleBuffer() {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            guard input.append(buffer) else { break }
            if duration > 0 {
                progress(min(1, CMSampleBufferGetPresentationTimeStamp(buffer).seconds / duration))
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error ?? reader.error {
            throw MediaEngineError.exportFailed(error.localizedDescription)
        }
    }

    // MARK: - Export

    private static func export(
        _ asset: AVAsset, preset: String, to destination: URL, fileType: AVFileType, progress: @escaping Progress
    ) async throws {
        guard let created = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw MediaEngineError.exportFailed(String(localized: "Can't convert \(destination.lastPathComponent)"))
        }
        // Only read for its progress stream while this function awaits the export.
        nonisolated(unsafe) let session = created
        session.shouldOptimizeForNetworkUse = true
        let monitor = Task {
            for await state in session.states(updateInterval: 0.25) {
                if case let .exporting(exportProgress) = state {
                    progress(exportProgress.fractionCompleted)
                }
            }
        }
        defer { monitor.cancel() }
        try await session.export(to: destination, as: fileType)
    }
}
