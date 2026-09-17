import AVFoundation
import CoreGraphics
import ImageIO
import Ollin
import os
import Testing

/// Video and GIF export correctness: encode a short clip from a tiny
/// deterministic sketch and verify the written file's structure — codec,
/// container, dimensions, duration, frame count, and loop metadata. (Pixel
/// correctness is the snapshot tests' job; these prove the encoding wrapper.)
///
/// Serialized because they share the GPU; gated on a Metal device so they skip
/// on a GPU-less machine instead of failing.
@Suite(.serialized)
@MainActor
struct VideoExportTests {

    @Test(.enabled(if: Snapshot.hasMetal))
    func h264ExportWritesPlayableMP4() async throws {
        let path = ollinTempPath("ollin-video-test.mp4")
        defer { try? FileManager.default.removeItem(atPath: path) }
        OllinApp.exportVideo(MovingDot(), to: path, frames: 12, fps: 30)

        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let duration = try await asset.load(.duration)
        #expect(abs(duration.seconds - 12.0 / 30) < 0.01)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let size = try await track.load(.naturalSize)
        #expect(Int(size.width) == 160 && Int(size.height) == 160)
        let format = try #require(try await track.load(.formatDescriptions).first)
        #expect(format.mediaSubType == .h264)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aBroadcastRateLandsEveryFrameOnItsFraction() async throws {
        let path = ollinTempPath("ollin-video-ntsc.mp4")
        defer { try? FileManager.default.removeItem(atPath: path) }
        OllinApp.exportVideo(MovingDot(), to: path, frames: 30, fps: .ntsc)

        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        // One frame is 1001/30000 s on the track's own clock, not 1/29.97.
        let step = try await track.load(.minFrameDuration)
        #expect(abs(step.seconds - 1001.0 / 30000) < 1e-9)
        let nominal = try await track.load(.nominalFrameRate)
        #expect(abs(Double(nominal) - 30000.0 / 1001) < 0.01)
        let duration = try await asset.load(.duration)
        #expect(abs(duration.seconds - 30 * 1001.0 / 30000) < 0.01)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func hevcExportAtABitrateWritesQuickTime() async throws {
        let path = ollinTempPath("ollin-video-test.mov")
        defer { try? FileManager.default.removeItem(atPath: path) }
        OllinApp.exportVideo(MovingDot(), to: path, frames: 12, fps: 30,
                             codec: .hevc, bitsPerSecond: 2_000_000)

        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let format = try #require(try await track.load(.formatDescriptions).first)
        #expect(format.mediaSubType == .hevc)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func gifExportLoopsAndDownscales() throws {
        let path = ollinTempPath("ollin-gif-test.gif")
        defer { try? FileManager.default.removeItem(atPath: path) }
        // 25 fps is a whole-centisecond rate (4/100s), so the frame count is
        // used exactly as requested.
        OllinApp.exportGIF(MovingDot(), to: path, frames: 10, fps: 25, width: 80)

        let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 10)
        let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        #expect(gif?[kCGImagePropertyGIFLoopCount] as? Int == 0)   // 0 = loop forever
        let frame = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(frame.width == 80 && frame.height == 80)
        let frameProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let frameGIF = frameProperties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        #expect(frameGIF?[kCGImagePropertyGIFDelayTime] as? Double == 0.04)
    }

    /// A GIF export's peak does not rise with its length: the same sketch at
    /// six times the frames peaks where the short run did. Holding the frames
    /// would have added about 90 MB at this size; the bound is well under
    /// that, with room for whatever else the suite is doing meanwhile.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aGIFExportsPeakDoesNotRiseWithItsLength() throws {
        let short = ollinTempPath("ollin-gif-peak-short.gif"), long = ollinTempPath("ollin-gif-peak-long.gif")
        defer { try? FileManager.default.removeItem(atPath: short); try? FileManager.default.removeItem(atPath: long) }
        let sampler = FootprintSampler()
        sampler.start()
        OllinApp.exportGIF(Wander(), to: short, frames: 20, fps: 25)
        let shortPeak = sampler.stop()
        sampler.start()
        OllinApp.exportGIF(Wander(), to: long, frames: 120, fps: 25)
        let longPeak = sampler.stop()
        #expect(longPeak - shortPeak < 40 * 1024 * 1024,
                "short \(shortPeak / 1_048_576) MB, long \(longPeak / 1_048_576) MB")
        let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: long) as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 120)
    }
}

/// The process footprint, read every few milliseconds on a plain thread while
/// an export runs on this one, so the peak inside the run is what is measured.
private final class FootprintSampler: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (peak: 0, running: false))

    func start() {
        state.withLock { $0 = (0, true) }
        let thread = Thread { [state] in
            while state.withLock({ $0.running }) {
                let now = GIFMemoryTests.footprint()
                state.withLock { if now > $0.peak { $0.peak = now } }
                usleep(3000)
            }
        }
        thread.start()
    }

    func stop() -> Int {
        state.withLock { $0.running = false; return $0.peak }
    }
}

/// A disc wandering over a flat field at a size worth measuring.
private final class Wander: Sketch {
    override var canvasSize: CanvasSize { .square(480) }

    override func draw() {
        background(Color(red: 0.1, green: 0.2, blue: 0.3))
        noStroke()
        fill(Color(red: 1, green: 0.8, blue: 0.2))
        drawCircle(width * (0.2 + 0.6 * (time * 0.7).truncatingRemainder(dividingBy: 1)),
                   height * (0.3 + 0.4 * (time * 0.3).truncatingRemainder(dividingBy: 1)), 40)
    }
}

// MARK: - Fixture

/// A dot crossing a flat field — tiny, deterministic, cheap to encode.
private final class MovingDot: Sketch {
    override var canvasSize: CanvasSize { .square(160) }

    override func draw() {
        background(.black)
        noStroke()
        fill(.white)
        drawCircle(width * (0.2 + 0.6 * time), height / 2, 20)
    }
}
