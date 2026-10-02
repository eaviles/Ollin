import AVFoundation
import CoreGraphics
import Foundation
import Ollin
import OllinVideo
import Testing
@testable import OllinVision

/// A detector in step with an export: the frames a tracker reads during an
/// export are a function of the export's clock, never of how fast it ran. A
/// still feed publishes on that clock, a video's virtual playhead hands each
/// new frame to its tap, every analysis finishes before the frame that asked
/// for it is drawn, a model is loaded before the first frame is read, and an
/// analysis the live path started before the export lands before the export's
/// own. Each test drives an export synchronously, so the headless flag is never
/// held across a suspension.
@MainActor
@Suite struct ExportClockTests {

    /// A tracker that writes down what it was asked to do. `loadDelay` stands
    /// in for a model's load, `prepare` being where a tracker loads one;
    /// `firstAnalysisDelay` holds the first analysis back, the way a slow model
    /// holds one the live path started.
    final class CountingTracker: VisionTracking, @unchecked Sendable {
        private let lock = NSLock()
        private var analyses = 0
        private var started = 0
        private var prepared = false
        private var unprepared = 0
        private var finished: [Int] = []
        let loadDelay: Duration
        let firstAnalysisDelay: Duration

        init(loadDelay: Duration = .zero, firstAnalysisDelay: Duration = .zero) {
            self.loadDelay = loadDelay
            self.firstAnalysisDelay = firstAnalysisDelay
        }

        private func locked<T>(_ body: () -> T) -> T {
            lock.lock(); defer { lock.unlock() }
            return body()
        }

        /// How many analyses have finished.
        var count: Int { locked { analyses } }
        /// How many analyses ran before `prepare` had finished.
        var readBeforeLoaded: Int { locked { unprepared } }
        /// The order analyses finished in, by the order they started.
        var finishOrder: [Int] { locked { finished } }

        func prepare(for cgImage: CGImage) async {
            if locked({ prepared }) { return }
            try? await Task.sleep(for: loadDelay)
            locked { prepared = true }
        }

        func analyze(_ cgImage: CGImage, size: CGSize) async {
            let index = locked { () -> Int in
                if !prepared { unprepared += 1 }
                defer { started += 1 }
                return started
            }
            if index == 0 { try? await Task.sleep(for: firstAnalysisDelay) }
            locked {
                analyses += 1
                finished.append(index)
            }
        }
    }

    /// A small gray picture; the trackers here only count.
    private static func picture() -> Image { Image(width: 32, height: 24, color: Color(white: 0.5)) }

    /// A sketch reading a still feed through a counting tracker, the way the
    /// examples do: the feed made and started with the sketch, before any
    /// export, and the tracker attached the first time `draw()` reads it. It
    /// writes down how many analyses had landed by each frame.
    final class StillReader: Sketch {
        let feed: StillFrames = {
            let feed = StillFrames(ExportClockTests.picture(), rate: 4)
            feed.start()
            return feed
        }()
        var tracker = CountingTracker()
        var seen: [Int] = []
        private var attached = false

        override var canvasSize: CanvasSize { .square(64) }
        override func draw() {
            if !attached {
                attached = true
                SourceAnalyzers.analyzer(for: feed).register(tracker)
            }
            seen.append(tracker.count)
            background(.black)
        }
    }

    /// The picture is published four times a second of the export's clock,
    /// starting on its first frame, and each analysis has landed before the
    /// frame that published it is drawn. A tracker attached in that first
    /// draw reads the picture at once. Two exports read the same frames.
    @Test func aStillFeedIsReadOnTheExportsClock() throws {
        var runs: [[Int]] = []
        for _ in 0 ..< 2 {
            let sketch = StillReader()
            _ = try OllinApp.image(of: sketch, frame: 59)
            runs.append(sketch.seen)
        }
        let expected = (1 ... 4).flatMap { Array(repeating: $0, count: 15) }
        #expect(runs[0] == expected)
        #expect(runs[1] == expected)
    }

    /// A held clock publishes nothing: the settle draws of a still repeat the
    /// moment, so the frames read are the clock's alone.
    @Test func aHeldClockPublishesNothing() throws {
        let asked = OllinApp.exportSettle
        defer { OllinApp.exportSettle = asked }
        OllinApp.exportSettle = 30
        let sketch = StillReader()
        _ = try OllinApp.image(of: sketch, frame: 20)
        // Frames 0 and 15 published; the thirty settle draws of frame 20 did not.
        #expect(sketch.seen.last == 2)
        #expect(sketch.seen.count == 20 + 30)
    }

    /// A tracker's load is awaited before it reads the first frame of an
    /// export, where the live path lets frames pass by while a model loads.
    @Test func aModelIsLoadedBeforeTheFirstFrameIsRead() throws {
        let sketch = StillReader()
        sketch.tracker = CountingTracker(loadDelay: .milliseconds(300))
        _ = try OllinApp.image(of: sketch, frame: 15)
        #expect(sketch.tracker.readBeforeLoaded == 0)
        #expect(sketch.seen.first == 1)
        #expect(sketch.seen.last == 2)
    }

    /// An analysis the live path began before the export started finishes
    /// before the export's first one, so its answer can never land on top of
    /// a reading the export already took.
    @Test func anAnalysisInFlightLandsFirst() throws {
        let sketch = StillReader()
        sketch.tracker = CountingTracker(firstAnalysisDelay: .milliseconds(300))
        let analyzer = SourceAnalyzers.analyzer(for: sketch.feed)
        analyzer.register(sketch.tracker)
        // Offered outside any export: analyzed on a background task, which is
        // still asleep in its first analysis when the export begins.
        analyzer.submit(FrameBox(Self.picture().currentCGImage()))
        _ = try OllinApp.image(of: sketch, frame: 0)
        #expect(Array(sketch.tracker.finishOrder.prefix(2)) == [0, 1])
    }

    /// A sketch reading a playing video through a counting tracker.
    final class VideoReader: Sketch {
        var player: VideoPlayer?
        let tracker = CountingTracker()
        var seen: [Int] = []
        private var attached = false

        override var canvasSize: CanvasSize { .square(64) }
        override func setup() { player?.play() }
        override func draw() {
            if !attached, let player {
                attached = true
                SourceAnalyzers.analyzer(for: player).register(tracker)
            }
            seen.append(tracker.count)
            background(.black)
        }
    }

    /// Under an export the player is not playing, so the pump that feeds a
    /// tracker live has nothing; the frame under the virtual playhead goes to
    /// the tap instead, once each time it changes. A twelve-frames-a-second
    /// clip read for one second at sixty is twelve frames, the same twelve in
    /// every run.
    @Test func aVideoIsReadOnTheExportsClock() async throws {
        guard let url = await Self.writeClip() else { return }   // soft-skip: no encoder
        defer { try? FileManager.default.removeItem(at: url) }
        var runs: [[Int]] = []
        for _ in 0 ..< 2 {
            let sketch = VideoReader()
            sketch.player = try VideoPlayer(url: url)
            _ = try OllinApp.image(of: sketch, frame: 59)
            runs.append(sketch.seen)
        }
        #expect(runs[0].last == 12)
        #expect(runs[0] == runs[1])
    }

    /// Twenty-four frames of gray at twelve a second, each a shade apart so
    /// every decoded frame is its own.
    private static func writeClip() async -> URL? {
        let side = 64
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-export-clock-\(UUID().uuidString).mp4")
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return nil }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: side,
            AVVideoHeightKey: side,
        ])
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
        for frame in 0 ..< 24 {
            while !input.isReadyForMoreMediaData {
                try? await Task.sleep(for: .milliseconds(10))
            }
            guard let pool = adaptor.pixelBufferPool else { return nil }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { return nil }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, Int32(40 + frame * 8), CVPixelBufferGetBytesPerRow(buffer) * side)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 12))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return writer.status == .completed ? url : nil
    }
}
