import Foundation
import Testing
@testable import Ollin

/// A GIF is held whole in memory until the file is laid down, so its cost
/// rises with the frame count where a video's does not. These pin the estimate
/// the export prints against what was actually measured, and pin when it is
/// worth printing at all.
@Suite
struct GIFMemoryTests {

    /// Peak physical footprint measured on one M2 while exporting the same
    /// sketch at two sizes and four lengths, in megabytes, beside the ~120 MB
    /// the renderer itself holds through a run of any length. The estimate is
    /// the line through these points, so a change to it has to answer to them.
    static let measured: [(frames: Int, width: Int, height: Int, peakMB: Double)] = [
        (150, 480, 480, 451.5),
        (300, 480, 480, 816.3),
        (600, 480, 480, 1536.0),
        (60, 1080, 1080, 817.3),
        (120, 1080, 1080, 1536.0),
    ]
    static let rendererMB = 120.0

    @Test
    func theEstimateMatchesWhatWasMeasured() {
        for run in Self.measured {
            let estimate = Double(OllinApp.gifPeakBytes(frames: run.frames, width: run.width,
                                                        height: run.height)) / 1_048_576
            let observed = run.peakMB - Self.rendererMB
            let off = abs(estimate - observed) / observed
            #expect(off < 0.10, "\(run.frames) at \(run.width): estimated \(estimate) MB against \(observed) MB")
        }
    }

    @Test
    func theEstimateRisesWithTheFrameCountAndWithTheArea() {
        let one = OllinApp.gifPeakBytes(frames: 100, width: 480, height: 480)
        #expect(OllinApp.gifPeakBytes(frames: 200, width: 480, height: 480) == one * 2)
        // The height follows the width, so halving the flag quarters the cost.
        #expect(OllinApp.gifPeakBytes(frames: 100, width: 240, height: 240) == one / 4)
    }

    /// An ordinary short loop is the common case and must stay quiet, or the
    /// line stops meaning anything.
    @Test
    func aShortLoopSaysNothing() {
        let eightGB: UInt64 = 8 * 1024 * 1024 * 1024
        #expect(OllinApp.gifMemoryNote(frames: 100, width: 480, height: 480,
                                       physicalMemory: eightGB) == nil)
        #expect(OllinApp.gifMemoryNote(frames: 25, width: 1080, height: 1080,
                                       physicalMemory: eightGB) == nil)
    }

    @Test
    func aLongOneNamesTheCostAndBothWaysOut() throws {
        let eightGB: UInt64 = 8 * 1024 * 1024 * 1024
        let note = try #require(OllinApp.gifMemoryNote(frames: 600, width: 480, height: 480,
                                                       physicalMemory: eightGB))
        #expect(note.contains("1.3 GB"))       // 600 × 480 × 480 × 10 bytes
        #expect(note.contains("--gif-width 240"))
        #expect(note.contains("--export-video"))
    }

    /// The bar is a share of the machine, not a fixed number of bytes, so the
    /// same export speaks on a small machine and stays quiet on a large one.
    @Test
    func theBarFollowsTheMachine() {
        let frames = 200, side = 640
        let peak = UInt64(OllinApp.gifPeakBytes(frames: frames, width: side, height: side))
        #expect(OllinApp.gifMemoryNote(frames: frames, width: side, height: side,
                                       physicalMemory: peak * 8 - 1) != nil)
        #expect(OllinApp.gifMemoryNote(frames: frames, width: side, height: side,
                                       physicalMemory: peak * 8 + 1) == nil)
    }
}
