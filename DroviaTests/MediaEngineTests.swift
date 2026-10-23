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
        try await MediaEngine.makeGIF(source, destination: output, width: 80, progress: noProgress)
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

    @Test func removesAudioKeepingVideo() async throws {
        let source = try await makeVideo()
        let output = folder.url.appendingPathComponent("muted.mp4")
        try await MediaEngine.removeAudio(source, destination: output, fileType: .mp4, progress: noProgress)
        let asset = AVURLAsset(url: output)
        #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)
        #expect(try await !asset.loadTracks(withMediaType: .video).isEmpty)
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
