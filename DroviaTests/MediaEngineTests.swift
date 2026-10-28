import AVFoundation
@testable import Drovia
import ImageIO
import Testing
import UniformTypeIdentifiers

struct MediaEngineTests {
    private let folder: TemporaryFolder
    private let noProgress: MediaEngine.Progress = { _ in }

    init() throws {
        folder = try TemporaryFolder()
    }

    // MARK: Fixtures

    /// A one-second 160×90 H.264 video without sound.
    private func makeVideo(_ name: String = "clip.mp4", fileType: AVFileType = .mp4) async throws -> URL {
        let url = folder.url.appendingPathComponent(name)
        let writer = try AVAssetWriter(outputURL: url, fileType: fileType)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 160, AVVideoHeightKey: 90,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 160, kCVPixelBufferHeightKey as String: 90,
        ])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0 ..< 10 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            var buffer: CVPixelBuffer?
            try CVPixelBufferPoolCreatePixelBuffer(nil, #require(adaptor.pixelBufferPool), &buffer)
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            memset(CVPixelBufferGetBaseAddress(pixels), Int32(frame * 25), CVPixelBufferGetDataSize(pixels))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: 10, timescale: 10))
        await writer.finishWriting()
        #expect(writer.status == .completed)
        return url
    }

    /// A half-second 440 Hz stereo tone.
    private func makeTone(_ name: String = "tone.wav") throws -> URL {
        let url = folder.url.appendingPathComponent(name)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 22050))
        buffer.frameLength = 22050
        for channel in 0 ..< 2 {
            for frame in 0 ..< 22050 {
                buffer.floatChannelData![channel][frame] = Float(sin(Double(frame) * 2 * .pi * 440 / 44100) * 0.5)
            }
        }
        try file.write(from: buffer)
        return url
    }

    /// The clip with the tone as its soundtrack and a creation date, as a QuickTime movie. `preset` decides
    /// whether the sound stays PCM (passthrough) or becomes AAC.
    private func makeVideoWithSound(
        _ name: String = "talk.mov",
        preset: String = AVAssetExportPresetHighestQuality
    ) async throws -> URL {
        let video = try await AVURLAsset(url: makeVideo("picture.mp4"))
        let sound = try AVURLAsset(url: makeTone("sound.wav"))
        let composition = AVMutableComposition()
        for (asset, type) in [(video, AVMediaType.video), (sound, .audio)] {
            let track = try #require(try await asset.loadTracks(withMediaType: type).first)
            let copy = try #require(composition.addMutableTrack(withMediaType: type, preferredTrackID: 0))
            try await copy.insertTimeRange(track.load(.timeRange), of: track, at: .zero)
        }
        let date = AVMutableMetadataItem()
        date.identifier = .quickTimeMetadataCreationDate
        date.value = "2024-05-01T10:00:00Z" as NSString
        date.dataType = kCMMetadataBaseDataType_UTF8 as String
        let session = try #require(AVAssetExportSession(asset: composition, presetName: preset))
        session.metadata = [date]
        let url = folder.url.appendingPathComponent(name)
        try await session.export(to: url, as: .mov)
        return url
    }

    private func creationDate(of url: URL) async throws -> String? {
        let items = try await AVURLAsset(url: url).load(.metadata)
        return try await AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .quickTimeMetadataCreationDate)
            .first?.load(.stringValue)
    }

    private func videoSize(_ url: URL) async throws -> CGSize {
        let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
        let (size, transform) = try await track.load(.naturalSize, .preferredTransform)
        let rect = CGRect(origin: .zero, size: size).applying(transform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }

    // MARK: Video

    @Test func rewrapsMP4AsMOV() async throws {
        let source = try await makeVideo()
        let output = folder.url.appendingPathComponent("clip.mov")
        try await MediaEngine.convert(source, to: .mov, destination: output, progress: noProgress)
        #expect(try await videoSize(output) == CGSize(width: 160, height: 90))
    }

    @Test func makesLoopingGIF() async throws {
        let source = try await makeVideo()
        let output = folder.url.appendingPathComponent("clip.gif")
        let isCut = try await MediaEngine.makeGIF(source, destination: output, width: 80, progress: noProgress)
        #expect(!isCut)
        let gif = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        #expect(CGImageSourceGetCount(gif) >= 10)
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(gif, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 80)
    }

    @Test func rotatesByTransformOnly() async throws {
        let source = try await makeVideo()
        let output = folder.url.appendingPathComponent("rotated.mp4")
        try await MediaEngine.rotateClockwise(source, destination: output, fileType: .mp4, progress: noProgress)
        #expect(try await videoSize(output) == CGSize(width: 90, height: 160))
    }

    @Test func rotationTransformKeepsPictureAtOrigin() {
        let size = CGSize(width: 160, height: 90)
        var transform = CGAffineTransform.identity
        for _ in 0 ..< 4 {
            transform = MediaEngine.rotatedClockwise(transform, naturalSize: size)
            let rect = CGRect(origin: .zero, size: size).applying(transform)
            #expect(abs(rect.minX) < 0.001 && abs(rect.minY) < 0.001)
        }
        #expect(transform.a == 1 && transform.d == 1)
    }

    @Test func saysWhenGIFIsCutShort() async throws {
        let output = folder.url.appendingPathComponent("short.gif")
        let isCut = try await MediaEngine.makeGIF(
            makeVideo(), destination: output, width: 80, maxDuration: 0.5, progress: noProgress
        )
        #expect(isCut)
    }

    @Test func removesAudioKeepingVideoAndCreationDate() async throws {
        let source = try await makeVideoWithSound()
        let output = folder.url.appendingPathComponent("muted.mov")
        try await MediaEngine.removeAudio(source, destination: output, fileType: .mov, progress: noProgress)
        let asset = AVURLAsset(url: output)
        #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)
        #expect(try await !asset.loadTracks(withMediaType: .video).isEmpty)
        #expect(try await creationDate(of: output) != nil)
    }

    @Test func rotationKeepsCreationDate() async throws {
        let output = folder.url.appendingPathComponent("turned.mov")
        try await MediaEngine.rotateClockwise(
            makeVideoWithSound(), destination: output, fileType: .mov, progress: noProgress
        )
        #expect(try await creationDate(of: output) != nil)
    }

    @Test func mutingSilentVideoSaysSo() async throws {
        await #expect(throws: MediaEngineError.self) {
            try await MediaEngine.removeAudio(
                makeVideo(), destination: folder.url.appendingPathComponent("m.mp4"), fileType: .mp4,
                progress: noProgress
            )
        }
    }

    @Test func convertsMOVWithPCMSoundToMP4() async throws {
        // PCM can't go into MP4 as is; the export session's own check doesn't know that.
        let source = try await makeVideoWithSound("pcm.mov", preset: AVAssetExportPresetPassthrough)
        let output = folder.url.appendingPathComponent("pcm.mp4")
        try await MediaEngine.convert(source, to: .mp4, destination: output, progress: noProgress)
        #expect(try await !AVURLAsset(url: output).loadTracks(withMediaType: .audio).isEmpty)
    }

    @Test func videoWithoutSoundCantBecomeAudio() async throws {
        let source = try await makeVideo()
        await #expect(throws: MediaEngineError.self) {
            try await MediaEngine.convertAudio(
                source,
                to: .m4a,
                destination: folder.url.appendingPathComponent("x.m4a"),
                progress: noProgress
            )
        }
    }

    // MARK: Audio

    @Test(arguments: [AudioFormat.m4a, .aiff])
    func convertsWAV(to format: AudioFormat) async throws {
        let source = try makeTone()
        let output = folder.url.appendingPathComponent("tone.\(format.rawValue)")
        try await MediaEngine.convertAudio(source, to: format, destination: output, progress: noProgress)
        let duration = try await AVURLAsset(url: output).load(.duration).seconds
        #expect(abs(duration - 0.5) < 0.1)
    }

    @Test(arguments: [AudioFormat.wav, .aiff])
    func keepsHighResolutionAudio(as format: AudioFormat) async throws {
        // The tone is 32-bit float; it used to come out as 16-bit.
        let output = folder.url.appendingPathComponent("copy.\(format.rawValue)")
        try await MediaEngine.convertAudio(makeTone(), to: format, destination: output, progress: noProgress)
        #expect(try AVAudioFile(forReading: output).fileFormat.settings[AVLinearPCMBitDepthKey] as? Int == 24)
    }

    @Test func convertsM4ABackToWAV() async throws {
        let m4a = folder.url.appendingPathComponent("tone.m4a")
        try await MediaEngine.convertAudio(makeTone(), to: .m4a, destination: m4a, progress: noProgress)
        let wav = folder.url.appendingPathComponent("back.wav")
        try await MediaEngine.convertAudio(m4a, to: .wav, destination: wav, progress: noProgress)
        let file = try AVAudioFile(forReading: wav)
        #expect(file.fileFormat.sampleRate == 44100)
        #expect(file.length > 20000)
    }

    @Test func classifiesMediaTypes() {
        #expect(MediaEngine.isVideo(.mpeg4Movie) && MediaEngine.isVideo(.quickTimeMovie))
        #expect(MediaEngine.isAudio(.mp3) && MediaEngine.isAudio(.wav))
        #expect(!MediaEngine.isVideo(.mp3) && !MediaEngine.isAudio(.png))
    }
}
