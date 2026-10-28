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
        guard try await canPassThrough(asset, to: format) else {
            try await export(
                asset,
                preset: AVAssetExportPresetHighestQuality,
                to: destination,
                fileType: format.fileType,
                progress: progress
            )
            return
        }
        do {
            try await export(
                asset,
                preset: AVAssetExportPresetPassthrough,
                to: destination,
                fileType: format.fileType,
                progress: progress
            )
        } catch {
            // Some streams pass the checks but not the export; re-encoding still gets the file converted.
            try await export(
                asset,
                preset: AVAssetExportPresetHighestQuality,
                to: destination,
                fileType: format.fileType,
                progress: progress
            )
        }
    }

    /// Whether the streams can be copied as they are. The export session's own check only looks at the
    /// container: it lets ProRes or PCM audio through to MP4, and the export then fails.
    private static func canPassThrough(_ asset: AVAsset, to format: VideoFormat) async throws -> Bool {
        guard await AVAssetExportSession.compatibility(
            ofExportPreset: AVAssetExportPresetPassthrough, with: asset, outputFileType: format.fileType
        ) else { return false }
        guard format == .mp4 else { return true }
        let mp4Video: Set<FourCharCode> = [kCMVideoCodecType_H264, kCMVideoCodecType_HEVC]
        let mp4Audio: Set<FourCharCode> = [
            kAudioFormatMPEG4AAC,
            kAudioFormatMPEGLayer3,
            kAudioFormatAC3,
            kAudioFormatEnhancedAC3,
        ]
        for track in try await asset.load(.tracks) {
            let allowed: Set<FourCharCode>
            switch track.mediaType {
            case .video: allowed = mp4Video
            case .audio: allowed = mp4Audio
            default: continue
            }
            for description in try await track.load(.formatDescriptions)
                where !allowed.contains(CMFormatDescriptionGetMediaSubType(description))
            {
                return false
            }
        }
        return true
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
        // Nothing to remove: a "muted" copy would just be the same video again.
        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else { throw MediaEngineError.noAudio(source) }
        let composition = AVMutableComposition()
        for track in try await asset.loadTracks(withMediaType: .video) {
            guard let copy = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
            else { continue }
            // The video's own time range: a longer soundtrack would otherwise leave an empty tail.
            let range = try await track.load(.timeRange)
            try copy.insertTimeRange(range, of: track, at: range.start)
            copy.preferredTransform = try await track.load(.preferredTransform)
        }
        guard !composition.tracks.isEmpty else { throw MediaEngineError.noVideo(source) }
        try await export(
            composition,
            metadata: asset.load(.metadata),
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
            metadata: asset.load(.metadata),
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
    /// GIF delays are whole hundredths of a second, so the default of 10 fps plays at exactly the video's
    /// speed (12 fps would be stored as 8/100 s and play 4% fast). Returns whether the video was cut short.
    static func makeGIF(
        _ source: URL, destination: URL, width: Int, fps: Double = 10, maxDuration: Double = 30,
        progress: @escaping Progress
    ) async throws -> Bool {
        let asset = AVURLAsset(url: source)
        guard try await !asset.loadTracks(withMediaType: .video).isEmpty else { throw MediaEngineError.noVideo(source) }
        // Streams and broken files have no usable duration (NaN would crash the frame count below).
        let length = try await asset.load(.duration)
        guard length.isNumeric, length.seconds > 0 else { throw MediaEngineError.unsupported(source) }
        let duration = min(length.seconds, maxDuration)
        let isCut = length.seconds > maxDuration
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
        var previous: CGImage?
        for await result in generator.images(for: times) {
            // A frame that can't be decoded repeats the one before, so the GIF keeps the video's pace.
            guard let image = (try? result.image) ?? previous else { continue }
            previous = image
            CGImageDestinationAddImage(gif, image, frameProperties)
            written += 1
            progress(Double(written) / Double(frameCount))
        }
        try await removingOnFailure(destination) {
            guard written > 0, CGImageDestinationFinalize(gif) else { throw ImageEngineError.cannotWrite(.gif) }
        }
        return isCut
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
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw MediaEngineError.noAudio(source) }
        if format == .m4a {
            try await export(
                asset,
                preset: AVAssetExportPresetAppleM4A,
                to: destination,
                fileType: .m4a,
                progress: progress
            )
        } else {
            try await writePCM(from: asset, tracks: tracks, to: destination, format: format, progress: progress)
        }
    }

    /// Decodes to uncompressed PCM, keeping the source's quality: lossless sources keep their bit depth
    /// (24 or 32 bits; float as 24-bit), a single track keeps all its channels (5.1 stays 5.1), and several tracks
    /// (a video with mic and system audio) are mixed rather than all but the first dropped.
    private static func writePCM(
        from asset: AVAsset, tracks: [AVAssetTrack], to destination: URL, format: AudioFormat,
        progress: @escaping Progress
    ) async throws {
        let description = try await tracks[0].load(.formatDescriptions).first
        let basic = description.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
        let sampleRate = basic?.mSampleRate ?? 44100
        let duration = try await asset.load(.duration).seconds

        var pcm: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVLinearPCMBitDepthKey: basic.map(Self.bitDepth) ?? 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: format == .aiff,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let channels = Int(basic?.mChannelsPerFrame ?? 2)
        if tracks.count == 1, channels > 2, let layout = description.flatMap(Self.channelLayout) {
            pcm[AVNumberOfChannelsKey] = channels
            pcm[AVChannelLayoutKey] = layout
        } else {
            pcm[AVNumberOfChannelsKey] = min(max(channels, 1), 2)
        }
        let reader = try AVAssetReader(asset: asset)
        let output: AVAssetReaderOutput = tracks.count == 1
            ? AVAssetReaderTrackOutput(track: tracks[0], outputSettings: pcm)
            : AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: pcm)
        reader.add(output)
        let writer = try AVAssetWriter(outputURL: destination, fileType: format.fileType)
        // Settings the writer rejects would raise an exception (and end the app) when the input is made.
        guard writer.canApply(outputSettings: pcm, forMediaType: .audio) else {
            throw MediaEngineError.unsupported(destination)
        }
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: pcm)
        input.expectsMediaDataInRealTime = false
        writer.add(input)

        guard reader.startReading(), writer.startWriting() else {
            throw MediaEngineError.exportFailed(reader.error?.localizedDescription ?? writer.error?.localizedDescription
                ?? String(localized: "Can't convert \(destination.lastPathComponent)"))
        }
        writer.startSession(atSourceTime: .zero)
        // A failed or cancelled conversion leaves no truncated file behind.
        try await removingOnFailure(destination) {
            do {
                var reported = 0.0
                while let buffer = output.copyNextSampleBuffer() {
                    while !input.isReadyForMoreMediaData {
                        try await Task.sleep(for: .milliseconds(5))
                    }
                    guard input.append(buffer) else { break }
                    // Every percent, not every buffer: each report is a hop to the main actor.
                    let fraction = duration > 0 ? CMSampleBufferGetPresentationTimeStamp(buffer).seconds / duration : 0
                    if fraction - reported >= 0.01 {
                        reported = fraction
                        progress(min(1, fraction))
                    }
                }
            } catch {
                reader.cancelReading()
                writer.cancelWriting()
                throw error
            }
            input.markAsFinished()
            await writer.finishWriting()
            if let error = writer.error ?? reader.error {
                throw MediaEngineError.exportFailed(error.localizedDescription)
            }
        }
    }

    /// Integer bits per sample to write for a source: uncompressed and lossless formats say; compressed ones
    /// (AAC, MP3) don't have one and get 16. Floating-point sources get 24-bit integers, since the writer
    /// can't write floating-point WAV (and AIFF has none).
    private static func bitDepth(of format: AudioStreamBasicDescription) -> Int {
        switch format.mFormatID {
        case kAudioFormatLinearPCM where format.mFormatFlags & kAudioFormatFlagIsFloat != 0:
            24
        case kAudioFormatLinearPCM:
            [24, 32].contains(Int(format.mBitsPerChannel)) ? Int(format.mBitsPerChannel) : 16
        case kAudioFormatAppleLossless, kAudioFormatFLAC:
            // The flags hold the source depth: 1 = 16, 2 = 20, 3 = 24, 4 = 32 bits.
            switch format.mFormatFlags {
            case 2, 3: 24
            case 4: 32
            default: 16
            }
        default:
            16
        }
    }

    private static func channelLayout(of description: CMAudioFormatDescription) -> Data? {
        var size = 0
        guard let layout = CMAudioFormatDescriptionGetChannelLayout(description, sizeOut: &size), size > 0 else {
            return nil
        }
        return Data(bytes: layout, count: size)
    }

    // MARK: - Export

    /// - Parameter metadata: For compositions, which have none of their own: the source's creation date,
    ///   location and camera details, which would otherwise be lost.
    private static func export(
        _ asset: AVAsset,
        metadata: [AVMetadataItem]? = nil,
        preset: String,
        to destination: URL,
        fileType: AVFileType,
        progress: @escaping Progress
    ) async throws {
        guard let created = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw MediaEngineError.exportFailed(String(localized: "Can't convert \(destination.lastPathComponent)"))
        }
        // Only read for its progress stream while this function awaits the export.
        nonisolated(unsafe) let session = created
        session.shouldOptimizeForNetworkUse = true
        if let metadata {
            session.metadata = metadata
        }
        let monitor = Task {
            for await state in session.states(updateInterval: 0.25) {
                if case let .exporting(exportProgress) = state {
                    progress(exportProgress.fractionCompleted)
                }
            }
        }
        defer { monitor.cancel() }
        try await removingOnFailure(destination) {
            try await session.export(to: destination, as: fileType)
        }
    }
}
