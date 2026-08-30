import AVFoundation
import CoreGraphics
import Testing
@testable import Ollin

/// The live recorder's timeline, checked without any audio hardware.
///
/// The property that matters is placement: a buffer lands at the sample its
/// host-clock stamp says, a hole between stamps becomes silence rather than a
/// slide, and what comes after a hole stays where it was played. Every test
/// drives the lane directly with synthetic stamps, so the checks are exact.
@Suite
struct AudioCaptureSinkTests {

    /// One frame per sample value makes misplacement visible as a value shift.
    private func ramp(_ count: Int, from start: Float = 1) -> [Float] {
        var samples = [Float](repeating: 0, count: count * 2)
        for f in 0..<count {
            samples[f * 2] = start + Float(f)
            samples[f * 2 + 1] = -(start + Float(f))
        }
        return samples
    }

    private func drained(_ sink: AudioCaptureSink, from: Int64, frames: Int) -> [Float] {
        var mix = [Float](repeating: 0, count: frames * 2)
        sink.mix(into: &mix, from: from, frames: frames)
        return mix
    }

    @Test func aBufferLandsWhereItsStampSays() {
        let sink = AudioCaptureSink(sampleRate: 1000, startHostSeconds: 100)
        sink.ingest(ramp(10), frames: 10, atHostSeconds: 100.5)
        let mix = drained(sink, from: 0, frames: 1000)
        #expect(mix[499 * 2] == 0)
        #expect(mix[500 * 2] == 1)
        #expect(mix[509 * 2] == 10)
        #expect(mix[509 * 2 + 1] == -10)
        #expect(sink.framesReceived == 510)
    }

    @Test func jitterDefersToTheRunningCounter() {
        let sink = AudioCaptureSink(sampleRate: 1000, startHostSeconds: 0)
        sink.ingest(ramp(10), frames: 10, atHostSeconds: 0)
        // Stamped 20 ms late, which is jitter, not a gap: the frames must
        // continue at sample 10, not open a hole at sample 30.
        sink.ingest(ramp(10, from: 11), frames: 10, atHostSeconds: 0.03)
        let mix = drained(sink, from: 0, frames: 40)
        #expect(mix[9 * 2] == 10)
        #expect(mix[10 * 2] == 11)
        #expect(mix[19 * 2] == 20)
        #expect(mix[20 * 2] == 0)
    }

    @Test func aRealGapBecomesSilenceAndNothingSlides() {
        let sink = AudioCaptureSink(sampleRate: 1000, startHostSeconds: 0)
        sink.ingest(ramp(10), frames: 10, atHostSeconds: 0)
        // Stamped 500 ms on: a device that went away and came back. The sound
        // after the hole keeps its own time.
        sink.ingest(ramp(10, from: 100), frames: 10, atHostSeconds: 0.5)
        let mix = drained(sink, from: 0, frames: 600)
        #expect(mix[9 * 2] == 10)
        #expect(mix[250 * 2] == 0)
        #expect(mix[500 * 2] == 100)
        #expect(mix[509 * 2] == 109)
    }

    @Test func soundFromBeforeTheRecordingIsTrimmed() {
        let sink = AudioCaptureSink(sampleRate: 1000, startHostSeconds: 10)
        // The buffer started 5 ms before the recording did; only the tail
        // from the start onward may land.
        sink.ingest(ramp(10), frames: 10, atHostSeconds: 9.995)
        let mix = drained(sink, from: 0, frames: 20)
        #expect(mix[0] == 6)
        #expect(mix[4 * 2] == 10)
        #expect(mix[5 * 2] == 0)
        #expect(sink.framesReceived == 5)
    }

    @Test func lanesSumIntoTheSameMix() {
        let one = AudioCaptureSink(sampleRate: 1000, startHostSeconds: 0)
        let two = AudioCaptureSink(sampleRate: 1000, startHostSeconds: 0)
        one.ingest(ramp(10), frames: 10, atHostSeconds: 0)
        two.ingest(ramp(10), frames: 10, atHostSeconds: 0.005)
        var mix = [Float](repeating: 0, count: 20 * 2)
        one.mix(into: &mix, from: 0, frames: 20)
        two.mix(into: &mix, from: 0, frames: 20)
        #expect(mix[0] == 1)
        #expect(mix[5 * 2] == 6 + 1)
        #expect(mix[14 * 2] == 10)
        #expect(mix[15 * 2] == 0)
    }

    @Test func aLaneNeverFedStaysSilent() {
        let sink = AudioCaptureSink(sampleRate: 1000, startHostSeconds: 0)
        let mix = drained(sink, from: 0, frames: 100)
        #expect(mix.allSatisfy { $0 == 0 })
    }
}

/// The recorder against a real writer: synthetic frames in, a playable movie
/// out. No audio device is touched (the sound lanes just run silent), so this
/// holds up under a loaded parallel test run.
@Suite
@MainActor
struct SessionRecorderWriterTests {

    private final class Still: Sketch {
        override var canvasSize: CanvasSize { .square(64) }
    }

    private func solidFrame(_ size: Int) -> CGImage {
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                    | CGBitmapInfo.byteOrder32Little.rawValue)!
        context.setFillColor(CGColor(red: 0.9, green: 0.4, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return context.makeImage()!
    }

    @Test func aRecordingBecomesAPlayableMovie() async throws {
        let sketch = Still()
        let recorder = SessionRecorder(audio: .sketch)
        sketch.extend(recorder)
        recorder.setup(sketch)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-recorder-test-\(UInt32.random(in: 0..<UInt32.max)).mov")
        defer { try? FileManager.default.removeItem(at: url) }

        recorder.start(to: url)
        try #require(recorder.isRecording)
        #expect(sketch.isRecording)
        // The writer opens on its queue, and frames handed over before that
        // are dropped by design (real time never waits), so feed a healthy
        // number *and* a healthy stretch of clock. Under a loaded parallel
        // test run the sleeps stretch; only the floors matter, never a cap.
        let frame = solidFrame(64)
        var fed = 0
        for _ in 0..<1000 {
            if recorder.elapsed >= 0.6 && fed >= 30 { break }
            recorder.frameRendered(sketch, image: frame)
            fed += 1
            try await Task.sleep(for: .milliseconds(20))
        }
        let saved: URL? = await withCheckedContinuation { done in
            recorder.stop { done.resume(returning: $0) }
        }
        #expect(saved == url)
        #expect(!recorder.isRecording)

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        #expect(duration > 0.4)
        let video = try await asset.loadTracks(withMediaType: .video)
        try #require(video.count == 1)
        let size = try await video[0].load(.naturalSize)
        #expect(Int(size.width) == 64 && Int(size.height) == 64)
        // The sound lanes had nothing to say, and the track still exists and
        // spans the take: a synth that enters late lands mid-file, in sync.
        let audio = try await asset.loadTracks(withMediaType: .audio)
        try #require(audio.count == 1)
        let audioRange = try await audio[0].load(.timeRange)
        #expect(audioRange.duration.seconds > 0.2)
    }

    @Test func aCanvasSizeChangeFinishesTheFileCleanly() async throws {
        let sketch = Still()
        let recorder = SessionRecorder(audio: .none)
        sketch.extend(recorder)
        recorder.setup(sketch)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-recorder-size-\(UInt32.random(in: 0..<UInt32.max)).mov")
        defer { try? FileManager.default.removeItem(at: url) }

        recorder.start(to: url)
        try #require(recorder.isRecording)
        // Enough frames that some land after the writer has opened on its
        // queue (the first few are dropped by design; see above).
        let frame = solidFrame(64)
        for _ in 0..<30 {
            recorder.frameRendered(sketch, image: frame)
            try await Task.sleep(for: .milliseconds(20))
        }
        // A swapped-in sketch rendering at another size must end the file,
        // not corrupt it.
        recorder.frameRendered(sketch, image: solidFrame(48))
        #expect(!recorder.isRecording)
        // The stop above finishes asynchronously; wait for a readable movie.
        var videoTracks = 0
        for _ in 0..<100 {
            try await Task.sleep(for: .milliseconds(20))
            let asset = AVURLAsset(url: url)
            if let tracks = try? await asset.loadTracks(withMediaType: .video),
               tracks.count == 1 {
                videoTracks = tracks.count
                break
            }
        }
        #expect(videoTracks == 1)
    }
}
