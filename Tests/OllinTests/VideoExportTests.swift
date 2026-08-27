import AVFoundation
import CoreGraphics
import ImageIO
import Ollin
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
