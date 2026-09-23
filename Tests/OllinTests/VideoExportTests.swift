import AVFoundation
import CoreGraphics
import ImageIO
@testable import Ollin
import os
import Testing

/// Video and GIF export correctness: encode a short clip from a tiny
/// deterministic sketch and verify the written file's structure: codec,
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

    /// A GIF export holds no frame past the frame it was drawn in. See
    /// `exportKeepsNoFramePastItsOwn`.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aGIFExportKeepsNoFramePastItsOwn() throws {
        let path = ollinTempPath("ollin-gif-frames-alive.gif")
        defer { try? FileManager.default.removeItem(atPath: path) }
        exportKeepsNoFramePastItsOwn(frames: 120) {
            OllinApp.exportGIF(Wander(), to: path, frames: 120, fps: 25)
        }
        let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 120)
    }

    /// A video export holds no frame past the frame it was drawn in either:
    /// the encoder's own buffers come from its pool, and the frame handed to
    /// it is let go once it is drawn in.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aVideoExportKeepsNoFramePastItsOwn() throws {
        let path = ollinTempPath("ollin-video-frames-alive.mp4")
        defer { try? FileManager.default.removeItem(atPath: path) }
        exportKeepsNoFramePastItsOwn(frames: 60) {
            OllinApp.exportVideo(Wander(), to: path, frames: 60, fps: 30)
        }
    }

    /// The invariant: no piece of frame memory (the buffer the GPU read the
    /// frame back into, the image built over it) outlives its frame by more
    /// than the beat Metal takes to let a readback go, and every byte handed
    /// out has come home once the export returns. Holding frames is what
    /// would have moved an export's peak with its length.
    ///
    /// Read off memory the test hands the export (`OllinApp.frameMemory`)
    /// and never off the process footprint, which is not evidence here.
    /// The suite shares its process with every other suite in its shard, so
    /// the process footprint is the sum of what all of them allocate in the
    /// same seconds: it can fail on a neighbor's work, and it can equally
    /// pass while the export leaks, if a neighbor frees as much in the same
    /// window. `GIFMemoryTests` says the same of the writer. The hog here
    /// allocates and touches 200 MB in this process for the whole run and
    /// changes nothing, which is the point of it. The count of pieces handed
    /// out is checked too, so a drive that stopped asking the ledger for its
    /// memory could not pass by never being counted.
    private func exportKeepsNoFramePastItsOwn(frames: Int, _ export: () -> Void) {
        let ledger = FrameLedger()
        let hog = Hog(bytes: 200 * 1024 * 1024)
        hog.start()
        OllinApp.frameMemory = ledger
        export()
        OllinApp.frameMemory = nil
        hog.stop()
        // The last buffer comes home when Metal lets it go, which can be a
        // beat after the drive returns.
        var waited = 0
        while ledger.returned < ledger.handed, waited < 400 { usleep(5000); waited += 1 }

        // A frame's two pieces are its readback and the image built over it,
        // handed out in that order. The drive holds the pair for the frame
        // and no longer, but the readback is let go by Metal from a thread of
        // its own once the frame's commands are done, so the one before can
        // still be on its way home while the next frame's is handed out: the
        // runner showed two readbacks alive for a beat (2026-09-22), which a
        // byte bound of one readback and one image read as a hold. What a
        // hold is, and the only thing this refuses, is a piece alive while
        // frames keep being handed out: measured in hand-outs, a beat's lag
        // is two, a loaded machine's lag a frame or so more, and a held frame
        // reads as the whole run behind (118 over 60 frames).
        let frameBytes = 480 * 480 * 4
        let mostFramesAlive = Double(ledger.mostBytesAlive) / Double(frameBytes)
        #expect(ledger.longestLag <= 5,
                "a piece of frame memory was still alive \(ledger.longestLag) hand-outs after its own, two per frame: a readback may come home a beat after its frame, never a whole run; \(mostFramesAlive) frames' worth were alive at the peak: \(ledger.sizesAtPeak)")
        #expect(ledger.handed >= 2 * frames,
                "the export asked for \(ledger.handed) pieces of frame memory over \(frames) frames; a readback and an image per frame are expected")
        #expect(ledger.returned == ledger.handed,
                "\(ledger.handed - ledger.returned) of \(ledger.handed) pieces of frame memory never came home")
    }
}

/// Memory the test owns, handed to an export for every buffer the GPU reads a
/// frame back into and every image built over one, and counted as it comes
/// home. Every piece is numbered as it goes out, and `longestLag` is the
/// most hand-outs any piece was still alive after its own: the one number
/// that tells a held frame (alive for the rest of the run) from a readback
/// Metal let go of a beat late. `most` is the high-water mark of bytes alive.
private final class FrameLedger: ExportFrameMemory, @unchecked Sendable {
    private struct State {
        var alive = 0, most = 0, handed = 0, returned = 0, longestLag = 0
        var live: [UInt: (serial: Int, bytes: Int)] = [:]      // keyed by address
        var atPeak: [Int] = []
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    func allocate(byteCount: Int) -> UnsafeMutableRawPointer {
        var raw: UnsafeMutableRawPointer?
        precondition(posix_memalign(&raw, Int(getpagesize()), byteCount) == 0, "out of memory")
        let pointer = raw!, key = UInt(bitPattern: pointer)
        state.withLock {
            let serial = $0.handed
            if let oldest = $0.live.values.map(\.serial).min() {
                $0.longestLag = max($0.longestLag, serial - oldest)
            }
            $0.alive += byteCount; $0.handed += 1
            $0.live[key] = (serial, byteCount)
            if $0.alive > $0.most { $0.most = $0.alive; $0.atPeak = $0.live.values.map(\.bytes) }
        }
        return pointer
    }

    /// From whichever thread let go of the memory last, hence the lock.
    func release(_ pointer: UnsafeMutableRawPointer, byteCount: Int) {
        let key = UInt(bitPattern: pointer)
        free(pointer)
        state.withLock { $0.alive -= byteCount; $0.returned += 1; $0.live[key] = nil }
    }

    var mostBytesAlive: Int { state.withLock { $0.most } }
    /// The most hand-outs any piece was still alive after its own.
    var longestLag: Int { state.withLock { $0.longestLag } }
    /// What was alive at the high-water mark, each size with its count, for
    /// the failure to name.
    var sizesAtPeak: [Int: Int] {
        state.withLock { $0.atPeak.reduce(into: [:]) { $0[$1, default: 0] += 1 } }
    }
    var handed: Int { state.withLock { $0.handed } }
    var returned: Int { state.withLock { $0.returned } }
}

/// A neighbor doing its own work in the same process: a thread that takes
/// and touches `bytes` and holds them until told to stop. The test above
/// never sees it, and that is what it is here to show.
private final class Hog: @unchecked Sendable {
    private let bytes: Int
    private let stopped = OSAllocatedUnfairLock(initialState: false)
    private var thread: Thread?

    init(bytes: Int) { self.bytes = bytes }

    func start() {
        let bytes = bytes, stopped = stopped
        let thread = Thread {
            guard let block = malloc(bytes) else { return }
            memset(block, 0x5A, bytes)          // touched, so it is resident
            while !stopped.withLock({ $0 }) { usleep(1000) }
            free(block)
        }
        thread.start()
        self.thread = thread
    }

    func stop() { stopped.withLock { $0 = true } }
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

/// A dot crossing a flat field: tiny, deterministic, cheap to encode.
private final class MovingDot: Sketch {
    override var canvasSize: CanvasSize { .square(160) }

    override func draw() {
        background(.black)
        noStroke()
        fill(.white)
        drawCircle(width * (0.2 + 0.6 * time), height / 2, 20)
    }
}
