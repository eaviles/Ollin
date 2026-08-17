import CoreGraphics
import Ollin
import Testing

/// Behavioral probes for the state automata (`.cyclic`, `.excitable`,
/// `.briansBrain`, `.hodgepodge`), run headless on a 64-texel field and compared
/// **cell for cell** against a plain sequential CPU reference stepping the same
/// published rule from the same start. The match pins the shared state encoding
/// (s/(levels-1) in .r, decoded with rint), the exact neighbour counts under both
/// neighbourhood shapes, the toroidal wrap, and the injects: the full-texel stamps
/// override the seeded-noise start everywhere they land, so the initial state is
/// known by construction (abutting unit rects tile seamlessly under the
/// inside-biased fill ramp, which is what makes per-texel stamping exact).
///
/// A stamp's gray is chosen in sRGB so it lands on the wanted linear level, and
/// the readback decodes each texel to the nearest expected level; the levels used
/// here sit tens of 8-bit steps apart, far past the present pass's ±1 dither.
@Suite
@MainActor
struct StateAutomataTests {

    // MARK: The rules, against the reference

    @Test(.enabled(if: Snapshot.hasMetal))
    func cyclicMatchesTheSequentialReference() throws {
        // Six states, threshold 2, the eight-cell block: exercises the corner taps
        // and the threshold path. Every texel is stamped, so the start is known.
        let states = 6
        let start = randomGrid(levels: states, seed: 7)
        let sketch = probe(.cyclic(states: states, threshold: 2, range: 1,
                                   neighborhood: .moore, seed: 3),
                           stamps: fullStamps(start, levels: states))
        let gpu = try grid(sketch, generations: 12, levels: states)
        var reference = start
        for _ in 0 ..< 12 {
            reference = stepCyclic(reference, states: states, threshold: 2,
                                   range: 1, moore: true)
        }
        #expect(gpu == reference)
        #expect(gpu != start)   // the run must actually advance
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func excitableWaveMatchesTheReference() throws {
        // A four-state cycle sparked at a handful of cells: the rings the rule
        // grows (and the refractory tails behind them) must match step for step.
        let states = 4
        let sparks = [(10, 10), (40, 22), (41, 22), (20, 47)]
        let sketch = probe(.excitable(states: states),
                           stamps: sparks.map { (x: $0.0, y: $0.1, white: 1.0) })
        let gpu = try grid(sketch, generations: 9, levels: states)
        var reference = emptyGrid()
        for (x, y) in sparks { reference[y][x] = 1 }
        for _ in 0 ..< 9 {
            reference = stepExcitable(reference, states: states, threshold: 1,
                                      range: 1, moore: false)
        }
        #expect(gpu == reference)
        // And the wave is real: excitation left the stamped cells behind.
        #expect(gpu.joined().filter { $0 == 1 }.count > sparks.count)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func briansBrainMatchesTheReference() throws {
        // A deterministic sprinkle of firing cells; the boil must match exactly.
        var rng = LCG(seed: 11)
        var cells: Set<Int> = []
        while cells.count < 60 { cells.insert(rng.next(4096)) }
        let sparks = cells.sorted().map { (x: $0 % 64, y: $0 / 64, white: 1.0) }
        let sketch = probe(.briansBrain(), stamps: sparks)
        let gpu = try grid(sketch, generations: 8, levels: 3)
        var reference = emptyGrid()
        for s in sparks { reference[s.y][s.x] = 2 }
        for _ in 0 ..< 8 { reference = stepBrain(reference) }
        #expect(gpu == reference)
        #expect(gpu.joined().contains(2))   // still firing somewhere
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func hodgepodgeMatchesTheSequentialReference() throws {
        // Eleven levels (n = 10) keep the readback unambiguous; k1/k2/g exercise
        // all three branches (catch, worsen with the averaged sum, recover).
        let n = 10
        let start = randomGrid(levels: n + 1, seed: 19)
        let sketch = probe(.hodgepodge(states: n, k1: 2, k2: 3, g: 3,
                                       neighborhood: .moore, seed: 5),
                           stamps: fullStamps(start, levels: n + 1))
        let gpu = try grid(sketch, generations: 10, levels: n + 1)
        var reference = start
        for _ in 0 ..< 10 {
            reference = stepHodgepodge(reference, n: n, k1: 2, k2: 3, g: 3, moore: true)
        }
        #expect(gpu == reference)
        #expect(gpu != start)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func anUntouchedExcitableFieldStaysAtRest() throws {
        // Rest is a fixed point for the draw-to-spark pair: no inject garbage, no
        // noise fill where none was asked for.
        let excitable = try grid(probe(.excitable(), stamps: []), generations: 20, levels: 3)
        let brain = try grid(probe(.briansBrain(), stamps: []), generations: 20, levels: 3)
        #expect(excitable.allSatisfy { $0.allSatisfy { $0 == 0 } })
        #expect(brain.allSatisfy { $0.allSatisfy { $0 == 0 } })
    }

    // MARK: Probes and readback

    private func probe(_ sim: Sim, stamps: [(x: Int, y: Int, white: Double)])
    -> AutomatonProbeSketch {
        let sketch = AutomatonProbeSketch()
        sketch.probeSim = sim
        sketch.stamps = stamps
        return sketch
    }

    /// Every texel stamped with its wanted state, as an sRGB gray that lands on
    /// the state's linear level.
    private func fullStamps(_ grid: [[Int]], levels: Int) -> [(x: Int, y: Int, white: Double)] {
        var stamps: [(x: Int, y: Int, white: Double)] = []
        for y in 0 ..< 64 {
            for x in 0 ..< 64 {
                stamps.append((x: x, y: y,
                               white: srgb(Double(grid[y][x]) / Double(levels - 1))))
            }
        }
        return stamps
    }

    /// The rendered field decoded back to integer states: each texel's red byte
    /// matched to the nearest expected level. The levels used by these tests sit
    /// tens of bytes apart, so the present pass's ±1 dither cannot flip one.
    /// The headless drive renders draws 0...frame inclusive and the sim steps once
    /// per draw, so a probe read at `frame: g - 1` holds exactly `g` generations
    /// past its frame-1 stamp.
    private func grid(_ sketch: Sketch, generations: Int, levels: Int) throws -> [[Int]] {
        let image = try #require(OllinApp.image(of: sketch, frame: generations - 1))
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        if let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                               bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: info) {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        let bytes = (0 ..< levels).map { Int((srgb(Double($0) / Double(levels - 1)) * 255).rounded()) }
        return (0 ..< h).map { y in
            (0 ..< w).map { x in
                let v = Int(data[(y * w + x) * 4])
                return bytes.indices.min(by: { abs(bytes[$0] - v) < abs(bytes[$1] - v) })!
            }
        }
    }

    /// Linear light → the sRGB curve (the standard piecewise transfer), used both
    /// to pick a stamp's gray and to predict a level's readback byte.
    private func srgb(_ l: Double) -> Double {
        l <= 0.0031308 ? l * 12.92 : 1.055 * pow(l, 1 / 2.4) - 0.055
    }

    // MARK: Sequential references (toroidal, like the shader)

    private func emptyGrid() -> [[Int]] {
        [[Int]](repeating: [Int](repeating: 0, count: 64), count: 64)
    }

    private func randomGrid(levels: Int, seed: UInt64) -> [[Int]] {
        var rng = LCG(seed: seed)
        return (0 ..< 64).map { _ in (0 ..< 64).map { _ in rng.next(levels) } }
    }

    /// The neighbourhood's offsets: the block within `range`, or the diamond.
    private func offsets(range: Int, moore: Bool) -> [(Int, Int)] {
        var list: [(Int, Int)] = []
        for dy in -range ... range {
            for dx in -range ... range where !(dx == 0 && dy == 0) {
                if moore || abs(dx) + abs(dy) <= range { list.append((dx, dy)) }
            }
        }
        return list
    }

    private func stepCyclic(_ g: [[Int]], states: Int, threshold: Int,
                            range: Int, moore: Bool) -> [[Int]] {
        let taps = offsets(range: range, moore: moore)
        return (0 ..< 64).map { y in
            (0 ..< 64).map { x in
                let next = (g[y][x] + 1) % states
                let count = taps.count { g[(y + $0.1 + 64) % 64][(x + $0.0 + 64) % 64] == next }
                return count >= threshold ? next : g[y][x]
            }
        }
    }

    private func stepExcitable(_ g: [[Int]], states: Int, threshold: Int,
                               range: Int, moore: Bool) -> [[Int]] {
        let taps = offsets(range: range, moore: moore)
        return (0 ..< 64).map { y in
            (0 ..< 64).map { x in
                let s = g[y][x]
                if s == 0 {
                    let firing = taps.count { g[(y + $0.1 + 64) % 64][(x + $0.0 + 64) % 64] == 1 }
                    return firing >= threshold ? 1 : 0
                }
                return (s + 1) % states
            }
        }
    }

    /// 0 ready, 1 resting, 2 firing.
    private func stepBrain(_ g: [[Int]]) -> [[Int]] {
        let taps = offsets(range: 1, moore: true)
        return (0 ..< 64).map { y in
            (0 ..< 64).map { x in
                switch g[y][x] {
                case 2: return 1
                case 1: return 0
                default:
                    let firing = taps.count { g[(y + $0.1 + 64) % 64][(x + $0.0 + 64) % 64] == 2 }
                    return firing == 2 ? 2 : 0
                }
            }
        }
    }

    private func stepHodgepodge(_ g: [[Int]], n: Int, k1: Int, k2: Int,
                                g growth: Int, moore: Bool) -> [[Int]] {
        let taps = offsets(range: 1, moore: moore)
        return (0 ..< 64).map { y in
            (0 ..< 64).map { x in
                let s = g[y][x]
                var infected = 0, ill = 0, sum = s
                for (dx, dy) in taps {
                    let v = g[(y + dy + 64) % 64][(x + dx + 64) % 64]
                    sum += v
                    if v == n { ill += 1 } else if v > 0 { infected += 1 }
                }
                let ns: Int
                if s == 0 { ns = infected / k1 + ill / k2 }
                else if s == n { ns = 0 }
                else { ns = sum / (infected + 1) + growth }
                return min(ns, n)
            }
        }
    }
}

/// A tiny deterministic generator for the reference grids (no wall clock, no
/// process state, so a rerun stamps the same start).
private struct LCG {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 2862933555777941757 &+ 3037000493 }
    mutating func next(_ bound: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 33) % UInt64(bound))
    }
}

/// A 64-texel automaton field stamped once, on frame 1, with full-texel unit
/// rects (abutting fills tile seamlessly, so every stamped texel reads exactly
/// its gray), then left to evolve and drawn 1:1.
@MainActor
private final class AutomatonProbeSketch: Sketch {
    override var canvasSize: CanvasSize { .square(64) }
    var probeSim: Sim = .gameOfLife()
    var stamps: [(x: Int, y: Int, white: Double)] = []

    private var field: SimField!

    override func setup() {
        field = simField(probeSim, scale: 1)
    }

    override func draw() {
        background(.black)
        withField(field) {
            if frameCount == 1 {
                noStroke()
                for s in stamps {
                    fill(Color(white: s.white))
                    // A polygon, not a drawRect: the polygon renders on the
                    // triangle path, whose MSAA coverage is purely geometric, so
                    // the stamped texel resolves to alpha 1 and its neighbours to
                    // exactly 0. An SDF rect's analytic halo is about one render
                    // pixel wide, which at one texel per pixel leaves the
                    // edge-adjacent texels hovering right at the injects' 0.5
                    // alpha gate.
                    let x = Double(s.x), y = Double(s.y)
                    drawPolygon([Vector2(x, y), Vector2(x + 1, y),
                                 Vector2(x + 1, y + 1), Vector2(x, y + 1)])
                }
            }
        }
        drawImage(field.image, 0, 0)
    }
}
