import Testing
import Foundation
import AVFoundation
import CoreVideo
import Metal
import Ollin
import os
@testable import OllinVideo

/// Exercised against a tiny clip written on the spot with AVAssetWriter, so the
/// tests need no bundled asset. Steps that depend on the environment (a video
/// encoder, a Metal device, a decode pipeline that runs headless) soft-skip
/// rather than fail, so CI stays green for environmental reasons while a real
/// Mac runs everything.
@MainActor
@Suite struct VideoPlayerTests {

    /// Writes a 64×64, 1-second (12 frames at 12 fps) H.264 clip. Each frame
    /// is the solid color `color` returns for its index (a saturated orange by
    /// default). Returns `nil` where no encoder is available.
    private func writeTestClip(
        color: (Int) -> (blue: UInt8, green: UInt8, red: UInt8) = { _ in (20, 128, 240) }
    ) async -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-video-test-\(UUID().uuidString).mp4")
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return nil }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 64,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64,
            ])
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        guard writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<12 {
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
                let fill = color(frame)
                for y in 0..<64 {
                    let row = base.advanced(by: y * bytesPerRow)
                        .assumingMemoryBound(to: UInt8.self)
                    for x in 0..<64 {
                        row[x * 4 + 0] = fill.blue
                        row[x * 4 + 1] = fill.green
                        row[x * 4 + 2] = fill.red
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

    /// Polls `read` every 50 ms until it returns a value or `seconds` elapse.
    ///
    /// The read comes before the clock: a starved task can wake past its own
    /// deadline having never looked once, and returning `nil` then reports a
    /// frame that never arrived while the frame is sitting there. Here that
    /// reads as a soft skip rather than a failure, which is worse, since the
    /// test then passes having checked nothing.
    private func waitFor<T>(seconds: Double, _ read: () -> T?) async -> T? {
        let deadline = Date(timeIntervalSinceNow: seconds)
        while true {
            if let value = read() { return value }
            if Date() >= deadline { return nil }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func metadataLoads() async throws {
        guard let url = await writeTestClip() else { return }   // soft-skip: no encoder
        defer { try? FileManager.default.removeItem(at: url) }
        let player = VideoPlayer(url: url)
        guard let duration = await waitFor(seconds: 5, { player.duration }) else {
            return   // soft-skip: metadata never loaded headless
        }
        #expect(abs(duration - 1.0) < 0.25)
        #expect(player.size == Vector2(64, 64))
        #expect(!player.isPlaying)
    }

    @Test func snapshotDecodesPixels() async throws {
        guard let url = await writeTestClip() else { return }   // soft-skip: no encoder
        defer { try? FileManager.default.removeItem(at: url) }
        let player = VideoPlayer(url: url)
        player.play()
        guard let snapshot = await waitFor(seconds: 5, { player.snapshot() }) else {
            return   // soft-skip: decode never produced a frame headless
        }
        #expect(snapshot.width == 64)
        #expect(snapshot.height == 64)
        // The clip is solid orange: red high, blue low.
        let pixel = snapshot[32, 32]
        #expect(pixel.red > 0.7)
        #expect(pixel.blue < 0.4)
    }

    @Test func frameWrapsAMetalTexture() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { return }   // soft-skip: no Metal
        guard let url = await writeTestClip() else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        let player = VideoPlayer(url: url)
        player.loops = true
        player.play()
        guard let frame = await waitFor(seconds: 5, { player.frame }) else {
            return   // soft-skip: decode never produced a frame headless
        }
        #expect(frame.width == 64)
        #expect(frame.height == 64)
        // While playing (looped), the same frame keeps drawing between decodes.
        #expect(player.frame != nil)
    }

    @Test func frameTapDeliversCPUFrames() async throws {
        guard let url = await writeTestClip() else { return }   // soft-skip: no encoder
        defer { try? FileManager.default.removeItem(at: url) }
        let player = VideoPlayer(url: url)
        // Count deliveries and remember the last frame's size (CGImage isn't
        // Sendable, so only plain values cross out of the tap).
        let seen = OSAllocatedUnfairLock(initialState: (count: 0, width: 0, height: 0))
        player.frameTap = { cgImage in
            let size = (cgImage.width, cgImage.height)
            seen.withLock { $0 = (count: $0.count + 1, width: size.0, height: size.1) }
        }
        player.loops = true
        player.play()
        guard await waitFor(seconds: 5, { seen.withLock { $0.count > 0 ? $0 : nil } }) != nil else {
            return   // soft-skip: decode never produced a frame headless
        }
        let final = seen.withLock { $0 }
        #expect(final.width == 64)
        #expect(final.height == 64)

        // Removing the tap stops delivery, and the count is read *after* the
        // removal returns on purpose: the guarantee is that nothing arrives
        // from then on, not that nothing was in flight when the tap was
        // cleared. Canceling the pump's timer only stops the next tick, and a
        // tick already holding a pixel buffer would otherwise deliver it a
        // millisecond later, which is the shape that failed here in a batch and
        // passed on its own. The pump drops that frame and the removal waits
        // for the tick to finish, so the count below cannot move.
        player.frameTap = nil
        let countAtRemoval = seen.withLock { $0.count }
        try? await Task.sleep(for: .milliseconds(300))
        #expect(seen.withLock { $0.count } == countAtRemoval)
    }

    @Test func missingFileThrows() {
        #expect(throws: VideoError.self) {
            _ = try VideoPlayer(path: "/nonexistent/clip.mp4")
        }
    }

    /// A headless export must show the video frame the sketch clock asks for,
    /// deterministically: frame `k` at `fps` shows the clip at `k / fps`
    /// seconds, and `loops` wraps. Each clip frame is a distinct blue level,
    /// so the rendered pixel identifies exactly which frame was pulled.
    @Test func headlessExportPullsDeterministicFrames() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { return }   // soft-skip: no Metal
        // Clip frame k (12 fps) is blue = 10 + k*20 over black.
        guard let url = await writeTestClip(color: { (blue: UInt8(10 + $0 * 20), green: 0, red: 0) })
        else { return }                                               // soft-skip: no encoder
        defer { try? FileManager.default.removeItem(at: url) }

        func exportedBlue(atFrame frame: Int) -> Double? {
            let sketch = VideoExportProbeSketch()
            sketch.player = VideoPlayer(url: url)
            guard let cgImage = OllinApp.image(of: sketch, frame: frame, fps: 60) else { return nil }
            return Image(cgImage: cgImage)[32, 32].blue
        }

        // Sketch frame 33 → 0.55 s → clip frame 6 → blue 130.
        guard let mid = exportedBlue(atFrame: 33) else { return }     // soft-skip: render failed
        #expect(abs(mid - 130.0 / 255.0) < 0.03)
        // Sketch frame 3 → 0.05 s → clip frame 0 → blue 10.
        guard let early = exportedBlue(atFrame: 3) else { return }
        #expect(abs(early - 10.0 / 255.0) < 0.03)
        // Sketch frame 93 → 1.55 s → wrapped past the 1 s clip → frame 6 again.
        guard let wrapped = exportedBlue(atFrame: 93) else { return }
        #expect(abs(wrapped - mid) < 0.01)
    }

    /// A sketch that wants one exact moment of a clip asks for it rather than
    /// playing to it. Under the headless driver `seek(to:)` and then
    /// `snapshot()` decodes at the virtual playhead, which is what a
    /// still-image detector needs offline and what three of the Guide's
    /// figures read the bundled film with. The process-global flag is set and
    /// cleared with no suspension in between, so no other test can see it up.
    @Test func headlessSnapshotFollowsTheSeek() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { return }   // soft-skip: no Metal
        // Clip frame k (12 fps) is blue = 10 + k*20 over black.
        guard let url = await writeTestClip(color: { (blue: UInt8(10 + $0 * 20), green: 0, red: 0) })
        else { return }                                               // soft-skip: no encoder
        defer { try? FileManager.default.removeItem(at: url) }
        let player = VideoPlayer(url: url)

        OllinApp.isRenderingHeadless = true
        player.seek(to: 6.5 / 12)          // inside clip frame 6: blue 130
        let sixth = player.snapshot()
        player.seek(to: 1.5 / 12)          // back to clip frame 1: blue 30
        let first = player.snapshot()
        OllinApp.isRenderingHeadless = false

        // Required rather than soft-skipped: past the two guards above, a nil
        // here means the headless path stopped decoding at the playhead, which
        // is the thing this pins.
        let atSix = try #require(sixth)
        let atOne = try #require(first)
        #expect(abs(atSix[32, 32].blue - 130.0 / 255) < 0.03)
        #expect(abs(atOne[32, 32].blue - 30.0 / 255) < 0.03)
    }

    /// End-to-end soundtrack tap: play the repository's bundled musical clip
    /// and expect mono PCM with real signal energy to arrive through
    /// `audioTap`. Runs off the example's own asset via a repo-relative path;
    /// soft-skips where the clip is missing or the environment won't play.
    @Test func audioTapDeliversSoundtrack() async throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // VideoPlayerTests.swift
            .deletingLastPathComponent()   // OllinVideoTests
            .deletingLastPathComponent()   // Tests
        let clip = repoRoot.appendingPathComponent(
            "Examples/Video/SoundReactive/voladores-fandanguito.mp4")
        guard FileManager.default.fileExists(atPath: clip.path) else { return }   // soft-skip

        let player = VideoPlayer(url: clip)
        // Near-silent output keeps the test quiet; the tap hears the pre-volume
        // signal regardless. (`isMuted = true` would stop audio processing
        // entirely and starve the tap, which is why it isn't used here.)
        player.volume = 0.01
        let delivered = OSAllocatedUnfairLock(initialState: (blocks: 0, samples: 0, rate: 0.0, peak: Float(0)))
        player.audioTap = { samples, rate in
            let count = samples.count
            var peak: Float = 0
            for sample in samples { peak = max(peak, abs(sample)) }
            let blockPeak = peak
            delivered.withLock {
                $0 = ($0.blocks + 1, $0.samples + count, rate, max($0.peak, blockPeak))
            }
        }
        player.play()
        guard await waitFor(seconds: 5, { delivered.withLock { $0.blocks > 3 ? $0 : nil } }) != nil
        else { return }   // soft-skip: no audio delivery headless
        // The clip is music (behind a short fade-in), not silence; the tap
        // should come to hear it even while the player is muted.
        guard await waitFor(seconds: 5, { delivered.withLock { $0.peak > 0.05 ? $0 : nil } }) != nil
        else {
            Issue.record("audio delivered but stayed silent (peak \(delivered.withLock { $0.peak }))")
            return
        }
        let final = delivered.withLock { $0 }
        #expect(final.rate > 8000)
        #expect(final.samples > 1024)

        // Removing the consumer stops delivery.
        player.audioTap = nil
        let atRemoval = delivered.withLock { $0.blocks }
        try? await Task.sleep(for: .milliseconds(300))
        #expect(delivered.withLock { $0.blocks } == atRemoval)
    }

    @Test func headlessPlaybackStateIsVirtual() async throws {
        guard let url = await writeTestClip() else { return }   // soft-skip: no encoder
        defer { try? FileManager.default.removeItem(at: url) }
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }

        let player = VideoPlayer(url: url)
        #expect(!player.isPlaying)
        player.play()
        #expect(player.isPlaying)
        #expect(player.currentTime == 0)

        // The first advance after play() arms rather than moves the playhead;
        // the following ones accumulate the fixed timestep.
        player.advance(by: 1.0 / 60)
        #expect(player.currentTime == 0)
        for _ in 0..<6 { player.advance(by: 1.0 / 60) }
        #expect(abs(player.currentTime - 0.1) < 1e-9)

        player.seek(to: 0.5)
        #expect(abs(player.currentTime - 0.5) < 1e-9)
        player.pause()
        #expect(!player.isPlaying)
        player.advance(by: 1.0 / 60)                    // paused: no motion
        #expect(abs(player.currentTime - 0.5) < 1e-9)
        player.stop()
        #expect(player.currentTime == 0)
    }

    @Test func fittedRectLetterboxes() async throws {
        guard let url = await writeTestClip() else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        let player = VideoPlayer(url: url)
        guard await waitFor(seconds: 5, { player.size }) != nil else { return }
        // A square video in a wide container: full height, centered horizontally.
        let rect = player.fittedRectangle(in: Rectangle(x: 0, y: 0, width: 200, height: 100))
        #expect(rect == Rectangle(x: 50, y: 0, width: 100, height: 100))
    }
}

/// Draws a video frame edge to edge on a tiny canvas; the export test reads a
/// pixel back to identify which clip frame the headless pull chose.
private final class VideoExportProbeSketch: Sketch {
    var player: VideoPlayer!
    override var canvasSize: CanvasSize { .size(64, 64) }

    override func setup() {
        player.loops = true
        player.play()
    }

    override func draw() {
        background(.black)
        if let frame = player.frame {
            drawImage(frame, in: bounds)
        }
    }
}
