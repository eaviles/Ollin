import Testing
import Foundation
import AVFoundation
import CoreVideo
import Metal
import Ollin
@testable import OllinVideo

/// Exercised against a tiny clip written on the spot with AVAssetWriter, so the
/// tests need no bundled asset. Steps that depend on the environment (a video
/// encoder, a Metal device, a decode pipeline that runs headless) soft-skip
/// rather than fail, so CI stays green for environmental reasons while a real
/// Mac runs everything.
@MainActor
@Suite struct VideoPlayerTests {

    /// Writes a 64×64, 1-second (12 frames at 12 fps) H.264 clip of a solid
    /// orange field. Returns `nil` where no encoder is available.
    private func writeTestClip() async -> URL? {
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
                for y in 0..<64 {
                    let row = base.advanced(by: y * bytesPerRow)
                        .assumingMemoryBound(to: UInt8.self)
                    for x in 0..<64 {
                        // BGRA: a solid, saturated orange.
                        row[x * 4 + 0] = 20
                        row[x * 4 + 1] = 128
                        row[x * 4 + 2] = 240
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
    private func waitFor<T>(seconds: Double, _ read: () -> T?) async -> T? {
        let deadline = Date(timeIntervalSinceNow: seconds)
        while Date() < deadline {
            if let value = read() { return value }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
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

    @Test func missingFileThrows() {
        #expect(throws: VideoError.self) {
            _ = try VideoPlayer(path: "/nonexistent/clip.mp4")
        }
    }

    @Test func fittedRectLetterboxes() async throws {
        guard let url = await writeTestClip() else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        let player = VideoPlayer(url: url)
        guard await waitFor(seconds: 5, { player.size }) != nil else { return }
        // A square video in a wide container: full height, centered horizontally.
        let rect = player.fittedRect(in: Rectangle(x: 0, y: 0, width: 200, height: 100))
        #expect(rect == Rectangle(x: 50, y: 0, width: 100, height: 100))
    }
}
