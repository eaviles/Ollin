import CoreGraphics
import Ollin
import Testing

/// Behavioral probes for the `.sandpile` sim, run headless on a small field and read
/// back as integer grain counts (the state is exact: quarters in the texel, four
/// well-separated display levels, so the decode is unambiguous under the present
/// pass's ±1 dither).
///
/// The centerpiece is the abelian property itself: the settled pile depends only on
/// what was dropped where, not on the order of the topplings, so the GPU's parallel
/// sweeps interleaved with pouring must land in *exactly* the configuration a plain
/// sequential CPU stabilization reaches. That match pins the threshold, the gather,
/// the inject's whole-grain rounding (an anti-aliased fringe that poured fractional
/// sand would break it), and, in the edge-block variant, the open boundary. The
/// boundary test was verified against its counterfactual: with the shader's
/// out-of-field guard removed (the clamping sampler then reads the edge texel back
/// as its own neighbor, a reflecting wall), the settled edge pile keeps the grains
/// the reference sheds, and the test goes red.
@Suite
@MainActor
struct SandpileTests {

    @Test(.enabled(if: Snapshot.hasMetal))
    func settledPileMatchesTheSequentialReference() throws {
        // 60 frames of pouring one grain per frame onto a 3×3 block, interleaved
        // with 8 toppling passes a frame, then 40 more frames to settle. The
        // reference drops all 540 grains at once and stabilizes; by the abelian
        // property the two schedules must agree cell for cell.
        let gpu = try grains(probe(centerTexel: 32), frame: 100)
        #expect(isStable(gpu))
        #expect(gpu == stabilized(dropping: 60, onBlockCenteredAt: 32, 32))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func grainsFallOffTheOpenBoundary() throws {
        // The same pour two texels from the left edge: the avalanche spills over
        // it, and the grains that cross are gone. The open-boundary reference
        // matches only if the GPU sheds them too.
        let gpu = try grains(probe(centerTexel: 2), frame: 100)
        let reference = stabilized(dropping: 60, onBlockCenteredAt: 2, 32)
        #expect(isStable(gpu))
        #expect(gpu == reference)
        // And the dissipation is real: the settled field holds fewer grains than
        // were dropped, so a reflecting or wrapping boundary cannot fake the match.
        let kept = reference.reduce(0) { $0 + $1.reduce(0, +) }
        #expect(kept < 540)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func restFieldStaysEmpty() throws {
        // Zero grains everywhere is a fixed point: an unseeded field must stay
        // black (no inject garbage, no boundary leak).
        let empty = try grains(probe(centerTexel: 32, pourFrames: 0), frame: 30)
        #expect(empty.allSatisfy { $0.allSatisfy { $0 == 0 } })
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func sameRunReplaysExactly() throws {
        // The sim is a pure gather over a drawn seed: no rng, no atomics, no wall
        // clock, so a rerun is grain-identical.
        let a = try grains(probe(centerTexel: 32), frame: 80)
        let b = try grains(probe(centerTexel: 32), frame: 80)
        #expect(a == b)
    }

    // MARK: Probes and readback

    /// A configured probe (`Sketch`'s init is `required`, so settings ride stored
    /// properties, the `TuringProbeSketch` shape).
    private func probe(centerTexel: Int, pourFrames: Int = 60) -> SandpileProbeSketch {
        let sketch = SandpileProbeSketch()
        sketch.centerTexel = centerTexel
        sketch.pourFrames = pourFrames
        return sketch
    }

    /// The rendered field decoded to integer grains per texel. Stable counts sit at
    /// linear 0, ¼, ½, ¾, which the present pass encodes to sRGB bytes ≈ 0, 137,
    /// 188, 224; anything at or above 240 is a cell holding four or more (mid
    /// avalanche), reported as 4 so `isStable` can see it.
    private func grains(_ sketch: Sketch, frame: Int) throws -> [[Int]] {
        let image = try #require(OllinApp.image(of: sketch, frame: frame))
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        if let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                               bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: info) {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (0 ..< h).map { y in
            (0 ..< w).map { x in
                switch data[(y * w + x) * 4] {
                case ..<69: 0
                case ..<163: 1
                case ..<207: 2
                case ..<240: 3
                default: 4
                }
            }
        }
    }

    private func isStable(_ g: [[Int]]) -> Bool {
        g.allSatisfy { $0.allSatisfy { $0 <= 3 } }
    }

    /// The sequential reference: drop `grains` on each texel of a 3×3 block of an
    /// empty 64×64 table and topple until stable, with the open boundary (a
    /// toppling cell always loses four; grains sent off the table are gone). Runs
    /// as repeated parallel gathers for convenience, which the abelian property
    /// makes equivalent to any other order.
    private func stabilized(dropping grains: Int, onBlockCenteredAt cx: Int, _ cy: Int,
                            size: Int = 64) -> [[Int]] {
        var g = [[Int]](repeating: [Int](repeating: 0, count: size), count: size)
        for y in (cy - 1) ... (cy + 1) {
            for x in (cx - 1) ... (cx + 1) { g[y][x] = grains }
        }
        while g.contains(where: { $0.contains(where: { $0 >= 4 }) }) {
            var next = g
            for y in 0 ..< size {
                for x in 0 ..< size {
                    var z = g[y][x]
                    if z >= 4 { z -= 4 }
                    for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                        where (0 ..< size).contains(nx) && (0 ..< size).contains(ny)
                        && g[ny][nx] >= 4 { z += 1 }
                    next[y][x] = z
                }
            }
            g = next
        }
        return g
    }
}

/// A 64-texel sandpile poured one grain per frame onto a 3×3 block for the first
/// `pourFrames` frames, then left to settle. The pour rect is inset a quarter texel
/// inside the block's boundary, so the nine covered texel centers read full
/// brightness (the region ramp is full to the geometric edge) while the excluded
/// neighbors sit far enough into the anti-aliased halo that one grain's worth of
/// brightness rounds to nothing: the injection is exact by construction.
@MainActor
private final class SandpileProbeSketch: Sketch {
    override var canvasSize: CanvasSize { .square(64) }
    var centerTexel = 32
    var pourFrames = 60

    private var field: SimField!

    override func setup() {
        field = makeSimField(.sandpile(pour: 1, topplings: 8), scale: 1)
    }

    override func draw() {
        background(.black)
        withField(field) {
            if frameCount <= pourFrames {
                noStroke()
                fill(.white)
                drawRect(Double(centerTexel) - 0.75, 31.25, 2.5, 2.5)
            }
        }
        drawImage(field.image, 0, 0)
    }
}
