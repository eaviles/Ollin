import CoreGraphics
import Foundation
import Ollin
import Testing

/// The headless drives are one long synchronous loop with no run loop under
/// them, so nothing empties the autorelease pool unless the drive does it
/// itself. A frame's readback buffer, and everything a sketch asks the device
/// for, arrives autoreleased; left undrained, a long export grows by one
/// frame's worth of allocations per frame until the machine swaps.
///
/// These pin the drain rather than the symptom. Each frame drops one witness
/// into whatever pool is current and the witness counts how many of its kind
/// are standing: a drive that drains per frame never has two at once, and one
/// that does not has as many as it has drawn.
@Suite(.serialized)
@MainActor
struct HeadlessDrainTests {

    @Test(.enabled(if: Snapshot.hasMetal))
    func theSingleFrameDriveDrainsEachFrame() {
        PoolCount.start()
        #expect(OllinApp.image(of: WitnessSketch(), frame: 5) != nil)
        #expect(PoolCount.drawn > 5)
        #expect(PoolCount.deepest == 1)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theSequenceDriveDrainsEachFrame() throws {
        let directory = ollinTempPath("ollin-drain-sequence")
        defer { try? FileManager.default.removeItem(atPath: directory) }
        PoolCount.start()
        OllinApp.exportSequence(WitnessSketch(), to: directory, frames: 6, fps: 30)
        #expect(PoolCount.drawn == 6)
        #expect(PoolCount.deepest == 1)
    }

    /// A warmup frame is drawn and thrown away, which is the shape most likely
    /// to be read as costing nothing; it allocates exactly like a written one.
    @Test(.enabled(if: Snapshot.hasMetal))
    func warmupFramesDrainToo() throws {
        let directory = ollinTempPath("ollin-drain-warmup")
        defer { try? FileManager.default.removeItem(atPath: directory) }
        PoolCount.start()
        OllinApp.exportSequence(WitnessSketch(), to: directory, frames: 2, fps: 30,
                                skipSeconds: 6.0 / 30)
        #expect(PoolCount.drawn == 8)          // six warmed up, two written
        #expect(PoolCount.deepest == 1)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theContactSheetDrainsEachTile() {
        PoolCount.start()
        #expect(OllinApp.contactSheet(of: { WitnessSketch() }, seeds: [1, 2, 3],
                                      tileWidth: 64) != nil)
        #expect(PoolCount.drawn == 3)
        #expect(PoolCount.deepest == 1)
    }

    /// The vector drives never touch the GPU, but the sketch they run does, so
    /// they carry the same rule.
    @Test
    func theVectorDriveDrainsEachFrame() {
        PoolCount.start()
        #expect(!OllinApp.svg(of: WitnessSketch(), frame: 4).isEmpty)
        #expect(PoolCount.drawn == 5)
        #expect(PoolCount.deepest == 1)
    }
}

/// A sketch that leaves one witness in the frame's pool on its way through
/// `draw()`. Small on purpose: what is being measured is the pool, not the
/// picture.
private final class WitnessSketch: Sketch {
    override var canvasSize: CanvasSize { .square(96) }

    override func draw() {
        PoolWitness.drop()
        background(.black)
        fill(.white)
        drawCircle(width / 2, height / 2, 12 + Double(frameCount))
    }
}

/// The tally the witnesses keep. Every drive under test is synchronous on the
/// main thread, so a plain counter is the whole mechanism; the generation is
/// what keeps a witness left standing by a *failing* test from disturbing the
/// next one's count as it finally drains.
private enum PoolCount {
    nonisolated(unsafe) static var generation = 0
    nonisolated(unsafe) static var live = 0
    nonisolated(unsafe) static var deepest = 0
    nonisolated(unsafe) static var drawn = 0

    static func start() {
        generation += 1
        live = 0
        deepest = 0
        drawn = 0
    }
}

/// An object handed to whatever autorelease pool is current, which lives until
/// that pool is drained.
private final class PoolWitness: NSObject {
    private let generation = PoolCount.generation

    static func drop() {
        _ = Unmanaged.passRetained(PoolWitness()).autorelease()
    }

    override init() {
        super.init()
        PoolCount.live += 1
        PoolCount.drawn += 1
        PoolCount.deepest = max(PoolCount.deepest, PoolCount.live)
    }

    deinit {
        if generation == PoolCount.generation { PoolCount.live -= 1 }
    }
}
