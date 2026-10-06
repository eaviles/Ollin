import Testing
import Foundation
import AVFoundation
import CoreVideo
import Metal
import Ollin
import os
@testable import OllinVideo
import OllinTestSupport

/// Exercised against a tiny clip written on the spot with AVAssetWriter, so the
/// tests need no bundled asset. What depends on the environment (a video
/// encoder, a Metal device, a decode pipeline that runs headless, an audio
/// route the headless player delivers through) is probed once and named in
/// an `.enabled` trait, so a machine without it reports the skip rather than a
/// pass that checked nothing, and a real Mac runs everything.
@MainActor
@Suite struct VideoPlayerTests {

    nonisolated static var hasMetal: Bool { MTLCreateSystemDefaultDevice() != nil }

    /// Whether a clip can be written and read back here: the encoder writes
    /// one, a player loads it headless and reports its duration. Asked once.
    static let clipPlaysHere = Task<Bool, Never> { @MainActor in
        guard let url = await VideoPlayerTests().writeTestClip() else { return false }
        defer { try? FileManager.default.removeItem(at: url) }
        guard let player = try? VideoPlayer(url: url) else { return false }
        return (try? await waitFor(timeout: 5) { player.duration }) != nil
    }

    static let clipTrait: ConditionTrait = .enabled("no video encoder, or no headless decode, here") {
        await VideoPlayerTests.clipPlaysHere.value
    }

    /// The repository's bundled musical clip, for the soundtrack tap.
    static let musicClip = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // VideoPlayerTests.swift
        .deletingLastPathComponent()   // OllinVideoTests
        .deletingLastPathComponent()   // Tests
        .appendingPathComponent("Examples/Video/SoundReactive/voladores-fandanguito.mp4")

    /// What one play of the bundled clip delivered through a tap, and whether
    /// removing the tap stopped the delivery.
    struct Heard: Sendable {
        var blocks = 0
        var samples = 0
        var rate = 0.0
        var peak: Float = 0
        var stoppedOnRemoval = false
    }

    /// The bundled clip played once, near-silent, into a tap for a few seconds,
    /// then the tap removed and the player stopped and let go: `nil` where
    /// nothing was delivered in five seconds, which is how a headless process
    /// with no audio route reads, and which `audioDelivers` reports as the skip
    /// it is. The player lives only inside this probe, the way it lived only
    /// inside the test before: a player kept playing for the life of the
    /// process overflowed the tap thread's stack on the runner. (`isMuted =
    /// true` would stop audio processing entirely and starve the tap, which is
    /// why the volume is turned down instead.)
    static let heard = Task<Heard?, Never> { @MainActor in
        guard FileManager.default.fileExists(atPath: musicClip.path),
              let player = try? VideoPlayer(url: musicClip) else { return nil }
        defer { player.pause() }
        let delivered = OSAllocatedUnfairLock(initialState: Heard())
        player.volume = 0.01
        player.audioTap = { samples, rate in
            let count = samples.count
            var peak: Float = 0
            for sample in samples { peak = max(peak, abs(sample)) }
            let blockPeak = peak
            delivered.withLock {
                $0.blocks += 1
                $0.samples += count
                $0.rate = rate
                $0.peak = max($0.peak, blockPeak)
            }
        }
        player.play()
        guard (try? await waitFor(timeout: 5) { delivered.withLock { $0.blocks > 3 ? true : nil } }) != nil else { return nil }
        // The clip is music behind a short fade-in; give the peak a moment to climb.
        _ = try? await waitFor(timeout: 5) { delivered.withLock { $0.peak > 0.05 ? true : nil } }
        // Removing the consumer stops delivery.
        player.audioTap = nil
        let atRemoval = delivered.withLock { $0.blocks }
        try? await Task.sleep(for: .milliseconds(300))
        return delivered.withLock { heard in
            heard.stoppedOnRemoval = heard.blocks == atRemoval
            return heard
        }
    }

    static let audioDelivers: ConditionTrait = .enabled("the bundled clip is missing, or the headless player delivers no audio here") {
        await VideoPlayerTests.heard.value != nil
    }

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

    @Test(clipTrait) func metadataLoads() async throws {
        let url = try #require(await writeTestClip())
        defer { try? FileManager.default.removeItem(at: url) }
        let player = try VideoPlayer(url: url)
        let duration = try await waitFor(timeout: 5) { player.duration }
        #expect(abs(duration - 1.0) < 0.25)
        #expect(player.size == Vector2(64, 64))
        #expect(!player.isPlaying)
    }

    @Test(clipTrait) func snapshotDecodesPixels() async throws {
        let url = try #require(await writeTestClip())
        defer { try? FileManager.default.removeItem(at: url) }
        let player = try VideoPlayer(url: url)
        player.play()
        let snapshot = try await waitFor(timeout: 5) { player.snapshot() }
        #expect(snapshot.width == 64)
        #expect(snapshot.height == 64)
        // The clip is solid orange: red high, blue low.
        let pixel = snapshot[32, 32]
        #expect(pixel.red > 0.7)
        #expect(pixel.blue < 0.4)
    }

    @Test(clipTrait, .enabled(if: VideoPlayerTests.hasMetal, "needs Metal")) func frameWrapsAMetalTexture() async throws {
        let url = try #require(await writeTestClip())
        defer { try? FileManager.default.removeItem(at: url) }
        let player = try VideoPlayer(url: url)
        player.loops = true
        player.play()
        let frame = try await waitFor(timeout: 5) { player.frame }
        #expect(frame.width == 64)
        #expect(frame.height == 64)
        // While playing (looped), the same frame keeps drawing between decodes.
        #expect(player.frame != nil)
    }

    @Test(clipTrait) func frameTapDeliversCPUFrames() async throws {
        let url = try #require(await writeTestClip())
        defer { try? FileManager.default.removeItem(at: url) }
        let player = try VideoPlayer(url: url)
        // Count deliveries and remember the last frame's size (CGImage isn't
        // Sendable, so only plain values cross out of the tap).
        let seen = OSAllocatedUnfairLock(initialState: (count: 0, width: 0, height: 0))
        player.frameTap = { cgImage in
            let size = (cgImage.width, cgImage.height)
            seen.withLock { $0 = (count: $0.count + 1, width: size.0, height: size.1) }
        }
        player.loops = true
        player.play()
        _ = try await waitFor(timeout: 5) { seen.withLock { $0.count > 0 ? $0 : nil } }
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
        // The same missing file through the other two doors, so an
        // unreadable clip is an error whichever door was used.
        #expect(throws: VideoError.self) {
            _ = try VideoPlayer(url: URL(fileURLWithPath: "/nonexistent/clip.mp4"))
        }
        #expect(throws: VideoError.self) {
            _ = try VideoPlayer(resource: "nonexistent", withExtension: "mp4", in: .main)
        }
    }

    /// A file that is there and is not a movie opens, since nothing can tell
    /// until the system reads it, and then says why there are no frames.
    @Test func anUnreadableFileSaysWhy() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-not-a-movie-\(UUID().uuidString).mp4")
        try Data("this is not a movie".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let player = try VideoPlayer(url: url)
        #expect(player.unavailableReason == nil, "nothing has been read yet")
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        #expect(player.frame == nil)
        #expect(player.unavailableReason?.contains("could not be read") == true,
                "the reason: \(player.unavailableReason ?? "none")")
    }

    /// A headless export must show the video frame the sketch clock asks for,
    /// deterministically: frame `k` at `fps` shows the clip at `k / fps`
    /// seconds, and `loops` wraps. Each clip frame is a distinct blue level,
    /// so the rendered pixel identifies exactly which frame was pulled.
    @Test(clipTrait, .enabled(if: VideoPlayerTests.hasMetal, "needs Metal")) func headlessExportPullsDeterministicFrames() async throws {
        // Clip frame k (12 fps) is blue = 10 + k*20 over black.
        let url = try #require(await writeTestClip(color: { (blue: UInt8(10 + $0 * 20), green: 0, red: 0) }))
        defer { try? FileManager.default.removeItem(at: url) }

        func exportedBlue(atFrame frame: Int) throws -> Double {
            let sketch = VideoExportProbeSketch()
            sketch.player = try? VideoPlayer(url: url)
            return Image(cgImage: try OllinApp.image(of: sketch, frame: frame, fps: 60))[32, 32].blue
        }

        // Sketch frame 33 → 0.55 s → clip frame 6 → blue 130.
        let mid = try exportedBlue(atFrame: 33)
        #expect(abs(mid - 130.0 / 255.0) < 0.03)
        // Sketch frame 3 → 0.05 s → clip frame 0 → blue 10.
        let early = try exportedBlue(atFrame: 3)
        #expect(abs(early - 10.0 / 255.0) < 0.03)
        // Sketch frame 93 → 1.55 s → wrapped past the 1 s clip → frame 6 again.
        let wrapped = try exportedBlue(atFrame: 93)
        #expect(abs(wrapped - mid) < 0.01)
    }

    /// A sketch that wants one exact moment of a clip asks for it rather than
    /// playing to it. Under the headless driver `seek(to:)` and then
    /// `snapshot()` decodes at the virtual playhead, which is what a
    /// still-image detector needs offline and what three of the Guide's
    /// figures read the bundled film with. The process-global flag is set and
    /// cleared with no suspension in between, so no other test can see it up.
    @Test(clipTrait, .enabled(if: VideoPlayerTests.hasMetal, "needs Metal")) func headlessSnapshotFollowsTheSeek() async throws {
        // Clip frame k (12 fps) is blue = 10 + k*20 over black.
        let url = try #require(await writeTestClip(color: { (blue: UInt8(10 + $0 * 20), green: 0, red: 0) }))
        defer { try? FileManager.default.removeItem(at: url) }
        let player = try VideoPlayer(url: url)

        OllinApp.isRenderingHeadless = true
        player.seek(to: 6.5 / 12)          // inside clip frame 6: blue 130
        let sixth = player.snapshot()
        player.seek(to: 1.5 / 12)          // back to clip frame 1: blue 30
        let first = player.snapshot()
        OllinApp.isRenderingHeadless = false

        // Required: past the trait, a nil here means the headless path stopped
        // decoding at the playhead, which is the thing this pins.
        let atSix = try #require(sixth)
        let atOne = try #require(first)
        #expect(abs(atSix[32, 32].blue - 130.0 / 255) < 0.03)
        #expect(abs(atOne[32, 32].blue - 30.0 / 255) < 0.03)
    }

    /// End-to-end soundtrack tap: the repository's bundled musical clip, played
    /// once by the probe above, delivers mono PCM with real signal energy
    /// through `audioTap`, and removing the tap stops the delivery. The probe's
    /// trait refuses this where the clip is missing or the headless player
    /// delivers nothing.
    @Test(audioDelivers) func audioTapDeliversSoundtrack() async throws {
        let heard = try #require(await Self.heard.value)
        // The clip is music (behind a short fade-in), not silence; the tap
        // should come to hear it even while the player is turned down.
        #expect(heard.peak > 0.05, "audio delivered but stayed silent (peak \(heard.peak))")
        #expect(heard.rate > 8000)
        #expect(heard.samples > 1024)
        #expect(heard.stoppedOnRemoval)
    }

    @Test(clipTrait) func headlessPlaybackStateIsVirtual() async throws {
        let url = try #require(await writeTestClip())
        defer { try? FileManager.default.removeItem(at: url) }
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }

        let player = try VideoPlayer(url: url)
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

    @Test(clipTrait) func fittedRectLetterboxes() async throws {
        let url = try #require(await writeTestClip())
        defer { try? FileManager.default.removeItem(at: url) }
        let player = try VideoPlayer(url: url)
        _ = try await waitFor(timeout: 5) { player.size }
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
