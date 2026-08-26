import Testing
import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import Ollin
import OllinVideo
@testable import OllinVision

/// The frame-source seam: trackers attaching to any `FrameSource`, not just the
/// camera. A hand-driven source exercises the tap → analyzer → tracker path
/// with no capture hardware, and the video test runs a tracker over a playing
/// `VideoPlayer` end to end (soft-skipping where the environment can't encode
/// or decode video, like the rest of the video tests).
@MainActor
@Suite struct FrameSourceTests {

    /// A frame source the test feeds by hand: firing `frameTap` directly stands
    /// in for a capture queue delivering a frame.
    final class ManualFrameSource: FrameSource {
        var frameTap: FrameTap?
    }

    /// A white image with a filled black disk, as a `CGImage` frame.
    private func diskFrame(size: Int) -> CGImage {
        let image = Image(width: size, height: size, color: .white)
        let black = Color(white: 0)
        let c = Double(size) / 2, r = Double(size) / 4
        for y in 0..<size {
            for x in 0..<size {
                let dx = Double(x) - c, dy = Double(y) - c
                if dx * dx + dy * dy < r * r { image[x, y] = black }
            }
        }
        return image.currentCGImage()
    }

    /// Polls `read` every 50 ms until it returns a value or `seconds` elapse.
    private func waitFor<T>(seconds: Double, _ read: () -> T?) async -> T? {
        let deadline = Date(timeIntervalSinceNow: seconds)
        while Date() < deadline {
            if let value = read() { return value }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    @Test func trackerRunsOverAManualSource() async throws {
        let source = ManualFrameSource()
        let detector = ContourDetector(source)
        let frame = diskFrame(size: 200)

        // Attaching the tracker installed the analyzer's tap on the source.
        let tap = try #require(source.frameTap)
        // The tap takes a frame the way a capture queue would. Its analysis
        // runs on a background task, so nothing here waits on it: a deadline
        // over that task reads a saturated full-suite machine as a failure.
        tap(frame)

        // The deterministic drive: the same analyze path, awaited inline. A
        // loaded machine makes this slower, never absent.
        await SourceAnalyzers.analyzer(for: source).analyzeNow(FrameBox(frame))
        #expect(detector.count >= 1)
    }

    @Test func trackersOnOneSourceShareAnAnalyzer() {
        let source = ManualFrameSource()
        let other = ManualFrameSource()
        let first = SourceAnalyzers.analyzer(for: source)
        let second = SourceAnalyzers.analyzer(for: source)
        let elsewhere = SourceAnalyzers.analyzer(for: other)
        #expect(first === second)
        #expect(first !== elsewhere)
    }

    @Test func contoursTraceAPlayingVideo() async throws {
        guard let url = await writeDiskClip() else { return }   // soft-skip: no encoder
        defer { try? FileManager.default.removeItem(at: url) }
        let player = VideoPlayer(url: url)
        let detector = ContourDetector(player)
        player.loops = true
        player.play()

        // Decode proof first, through the player's own display output — if the
        // headless environment can't decode at all, soft-skip rather than fail.
        guard await waitFor(seconds: 5, { player.snapshot() }) != nil else { return }

        // The tap output decodes the same frames; the disk must trace.
        let found = await waitFor(seconds: 10) { detector.count >= 1 ? true : nil }
        #expect(found == true, "a high-contrast disk in the footage should produce contours")
    }

    /// Writes a tiny 128×128 H.264 clip of a black disk on white — high
    /// contrast, so contour detection over it is unambiguous. Returns `nil`
    /// where no encoder is available (the OllinVideoTests pattern).
    private func writeDiskClip() async -> URL? {
        let side = 128
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-vision-video-test-\(UUID().uuidString).mp4")
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return nil }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: side,
            AVVideoHeightKey: side,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: side,
                kCVPixelBufferHeightKey as String: side,
            ])
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        guard writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<24 {
            while !input.isReadyForMoreMediaData {
                try? await Task.sleep(for: .milliseconds(10))
            }
            guard let pool = adaptor.pixelBufferPool else { return nil }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { return nil }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
                let c = Double(side) / 2, r = Double(side) / 4
                for y in 0..<side {
                    let row = base.advanced(by: y * bytesPerRow)
                        .assumingMemoryBound(to: UInt8.self)
                    for x in 0..<side {
                        let dx = Double(x) - c, dy = Double(y) - c
                        let inside = dx * dx + dy * dy < r * r
                        let value: UInt8 = inside ? 0 : 255
                        row[x * 4 + 0] = value
                        row[x * 4 + 1] = value
                        row[x * 4 + 2] = value
                        row[x * 4 + 3] = 255
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            let time = CMTime(value: CMTimeValue(frame), timescale: 12)
            adaptor.append(buffer, withPresentationTime: time)
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { return nil }
        return url
    }
}
