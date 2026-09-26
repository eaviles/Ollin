import CoreGraphics
import Foundation
@testable import Ollin
import Testing

/// Behavioral probes for `.smoothLife`, run headless on a small field and read
/// back: the transition matches a plain double-precision CPU reference of the
/// published rule texel for texel, rest and crowding are the two fixed points
/// Life has (an empty field stays empty, a full one dies at once), and the
/// paper's glider, seeded as a notched disc, keeps its mass and travels at a
/// steady speed in a steady direction. Metal-gated.
@Suite
@MainActor
struct SmoothLifeTests {

    // MARK: The rule, against the reference

    /// A 64-texel field of random grays run two generations at radius 6, against a
    /// CPU reference of the same rule: the area-normalized disc and ring fillings
    /// with the one-texel anti-aliasing ramp at each rim, the sigmoid steps, and
    /// the discrete time-stepping. The steps are wider than the paper's here
    /// (0.1 and 0.2 against 0.028 and 0.147): at the paper's widths a texel whose
    /// ring filling sits within a float16 rounding of an interval's edge can
    /// land on either side after two generations (one did, by 0.086), and the
    /// formulas under test are the same at any width. A wrong weight or a wrong
    /// rim still moves texels by far more than the tolerance.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theTransitionMatchesTheReference() throws {
        var rng = LCG(seed: 5)
        // Grays up to 0.7, so the ring fillings land around the two intervals
        // rather than past them, and the second generation still has life in it.
        let start = (0 ..< 64).map { _ in (0 ..< 64).map { _ in Double(rng.next(1000)) / 999 * 0.7 } }
        for generations in 1 ... 2 {
            // A fresh sketch per render: the headless drive runs setup again but
            // keeps the frame count, so a reused one never stamps its seed.
            let sketch = SmoothLifeProbeSketch()
            sketch.probeSim = .smoothLife(radius: 6, intervalSoftness: 0.1, cellSoftness: 0.2)
            sketch.grays = start
            let gpu = try field(of: sketch, generations: generations)
            var reference = start
            for _ in 0 ..< generations {
                reference = stepSmoothLife(reference, radius: 6, alphaN: 0.1, alphaM: 0.2)
            }
            var worst = 0.0, at = (x: 0, y: 0), over = 0
            for y in 0 ..< 64 {
                for x in 0 ..< 64 {
                    let off = abs(gpu[y][x] - reference[y][x])
                    if off > worst { worst = off; at = (x, y) }
                    if off > 0.03 { over += 1 }
                }
            }
            #expect(worst < 0.03, "after \(generations): worst texel \(at) off by \(worst), gpu \(gpu[at.y][at.x]) vs \(reference[at.y][at.x]); \(over) texels over 0.03")
        }
        var reference = start
        for _ in 0 ..< 2 { reference = stepSmoothLife(reference, radius: 6, alphaN: 0.1, alphaM: 0.2) }
        // And the run advanced: the reference is not the start.
        let moved = zip(reference.joined(), start.joined()).filter { abs($0 - $1) > 0.2 }.count
        #expect(moved > 1000)
    }

    // MARK: The fixed points

    @Test(.enabled(if: Snapshot.hasMetal))
    func anEmptyFieldStaysEmptyAndAFullOneDies() throws {
        let empty = SmoothLifeProbeSketch()
        empty.probeSim = .smoothLife(radius: 6)
        let rest = try field(of: empty, generations: 20)
        #expect(rest.joined().max()! < 0.01)

        let full = SmoothLifeProbeSketch()
        full.probeSim = .smoothLife(radius: 6)
        full.grays = [[Double]](repeating: [Double](repeating: 1, count: 64), count: 64)
        // One generation: a ring filled past the survival interval kills every cell.
        let crowded = try field(of: full, generations: 1)
        #expect(crowded.joined().max()! < 0.01)
    }

    // MARK: The glider

    /// The paper's smooth glider, at its parameters, from the classic seed: a disc
    /// a little under the radius with a notch bitten out of one side. Over the
    /// run its mass settles into a band and holds there, and its centroid moves
    /// the same distance in the same direction between checkpoints, which is what
    /// a glider is and what a still life, a pulsing ring, or a dying blob is not.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theGliderKeepsItsMassAndTravels() throws {
        // One run to generation 100, measured at each checkpoint on the way.
        let generations = [40, 60, 80, 100]
        let run = try fields(of: SmoothLifeGliderSketch(), generations: generations)
        let checkpoints = try generations.map { generation -> (mass: Double, centroid: Vector2) in
            let values = try #require(run[generation])
            return (mass(of: values), centroid(of: values))
        }
        let masses = checkpoints.map(\.mass)
        // Alive, and steady: neither dying out nor filling the field, and the
        // spread between checkpoints small against the mass itself.
        #expect(masses.min()! > 200)
        #expect(masses.max()! < 2000)
        #expect((masses.max()! - masses.min()!) / masses.max()! < 0.15, "\(masses)")
        // Traveling: each 20 generations move the centroid by the same vector,
        // read across the field's wrap (a move of -105 on a 192 field is +87).
        func unwrap(_ d: Double) -> Double { d - (d / 192).rounded() * 192 }
        let moves = (1 ..< checkpoints.count).map { i -> Vector2 in
            let d = checkpoints[i].centroid - checkpoints[i - 1].centroid
            return Vector2(unwrap(d.x), unwrap(d.y))
        }
        for move in moves { #expect(move.length > 3, "\(moves)") }
        for pair in zip(moves, moves.dropFirst()) {
            #expect((pair.0 - pair.1).length < 0.25 * pair.0.length, "\(moves)")
        }
    }

    // MARK: Readback

    /// The rendered field decoded back to linear values, one per texel.
    private func field(of sketch: Sketch, generations: Int) throws -> [[Double]] {
        values(in: try #require(OllinApp.image(of: sketch, frame: generations - 1)))
    }

    /// The same readout after each of several generation counts, from one run to
    /// the largest: frame `g - 1` of the run is the field `field(of:generations: g)`
    /// reads, decoded as the run passes it.
    private func fields(of sketch: Sketch, generations: [Int]) throws -> [Int: [[Double]]] {
        var out: [Int: [[Double]]] = [:]
        guard let last = generations.max() else { return out }
        let wanted = Set(generations.map { $0 - 1 })
        try OllinApp.renderFrames(sketch, frames: last, fps: 60, skipSeconds: 0) { frame, index in
            guard wanted.contains(index), let image = frame.image else { return }
            out[index + 1] = values(in: image)
        }
        return out
    }

    private func values(in image: CGImage) -> [[Double]] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        if let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                               bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: info) {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (0 ..< h).map { y in
            (0 ..< w).map { x in linear(Double(data[(y * w + x) * 4]) / 255) }
        }
    }

    private func mass(of values: [[Double]]) -> Double { values.joined().reduce(0, +) }

    /// The mass-weighted center, read on the torus (the field wraps), so a glider
    /// crossing an edge keeps a continuous track.
    private func centroid(of values: [[Double]]) -> Vector2 {
        let h = values.count, w = values[0].count
        var sx = 0.0, cx = 0.0, sy = 0.0, cy = 0.0
        for y in 0 ..< h {
            for x in 0 ..< w {
                let m = values[y][x]
                let ax = Double(x) / Double(w) * 2 * .pi, ay = Double(y) / Double(h) * 2 * .pi
                sx += m * sin(ax); cx += m * cos(ax)
                sy += m * sin(ay); cy += m * cos(ay)
            }
        }
        func unwrap(_ s: Double, _ c: Double, _ n: Int) -> Double {
            var a = atan2(s, c)
            if a < 0 { a += 2 * .pi }
            return a / (2 * .pi) * Double(n)
        }
        return Vector2(unwrap(sx, cx, w), unwrap(sy, cy, h))
    }

    /// The sRGB curve back to linear light (the standard piecewise transfer).
    private func linear(_ s: Double) -> Double {
        s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
    }

    // MARK: The reference (toroidal, like the shader)

    /// One generation of the published rule in double precision: the disc of
    /// radius `radius / 3` and the ring out to `radius`, each an area-normalized
    /// average with a one-texel linear ramp across each rim, the sigmoid steps of
    /// width alpha, and the discrete transition as the new state.
    private func stepSmoothLife(_ f: [[Double]], radius: Double,
                                birth: ClosedRange<Double> = 0.278 ... 0.365,
                                survival: ClosedRange<Double> = 0.267 ... 0.445,
                                alphaN: Double = 0.028, alphaM: Double = 0.147) -> [[Double]] {
        let h = f.count, w = f[0].count
        let ri = radius / 3
        let reach = Int((radius + 0.5).rounded(.up))
        func sigma(_ x: Double, _ a: Double, _ alpha: Double) -> Double {
            1 / (1 + exp(-(x - a) * 4 / alpha))
        }
        var out = f
        for y in 0 ..< h {
            for x in 0 ..< w {
                var inner = 0.0, innerWeight = 0.0, outer = 0.0, outerWeight = 0.0
                for dy in -reach ... reach {
                    for dx in -reach ... reach {
                        let l = Double(dx * dx + dy * dy).squareRoot()
                        if l >= radius + 0.5 { continue }
                        let ring = min(1, max(0, l - ri + 0.5))
                        let rim = 1 - min(1, max(0, l - radius + 0.5))
                        let wi = 1 - ring, wo = ring * rim
                        let v = f[((y + dy) % h + h) % h][((x + dx) % w + w) % w]
                        inner += wi * v; innerWeight += wi
                        outer += wo * v; outerWeight += wo
                    }
                }
                let m = inner / innerWeight, n = outer / outerWeight
                let alive = sigma(m, 0.5, alphaM)
                let lower = birth.lowerBound + (survival.lowerBound - birth.lowerBound) * alive
                let upper = birth.upperBound + (survival.upperBound - birth.upperBound) * alive
                out[y][x] = sigma(n, lower, alphaN) * (1 - sigma(n, upper, alphaN))
            }
        }
        return out
    }
}

private struct LCG {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 2862933555777941757 &+ 3037000493 }
    mutating func next(_ bound: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 33) % UInt64(bound))
    }
}

/// A 64-texel SmoothLife field stamped once, on frame 1, every texel its own gray
/// as a full-texel unit polygon (abutting fills tile seamlessly, so each stamped
/// texel reads exactly its gray), then left to evolve and drawn 1:1.
@MainActor
private final class SmoothLifeProbeSketch: Sketch {
    override var canvasSize: CanvasSize { .square(64) }
    var probeSim: Sim = .smoothLife()
    /// The stamped grays, row by row; empty leaves the field at rest.
    var grays: [[Double]] = []

    private var field: SimField!

    override func setup() {
        field = makeSimField(probeSim, scale: 1)
    }

    override func draw() {
        background(.black)
        withField(field) {
            if frameCount == 1 {
                noStroke()
                for (y, row) in grays.enumerated() {
                    for (x, gray) in row.enumerated() where gray > 0 {
                        // A Color is sRGB-encoded, so the stamp is chosen on that
                        // curve to land on the wanted linear level.
                        fill(Color(white: gray <= 0.0031308 ? gray * 12.92 : 1.055 * pow(gray, 1 / 2.4) - 0.055))
                        let px = Double(x), py = Double(y)
                        drawPolygon([Vector2(px, py), Vector2(px + 1, py),
                                     Vector2(px + 1, py + 1), Vector2(px, py + 1)])
                    }
                }
            }
        }
        drawImage(field.image, 0, 0)
    }
}

/// The paper's glider on a 192-texel field at the paper's parameters: a disc a
/// little under the radius, with a smaller disc bitten out of one side, stamped
/// on frame 1 and left to run.
@MainActor
private final class SmoothLifeGliderSketch: Sketch {
    override var canvasSize: CanvasSize { .square(192) }
    private var field: SimField!

    override func setup() {
        field = makeSimField(.smoothLife(), scale: 1)
    }

    override func draw() {
        background(.black)
        withField(field) {
            if frameCount == 1 {
                noStroke()
                fill(.white)
                drawCircle(96, 96, 18)
                fill(.black)
                drawCircle(105, 96, 7)
            }
        }
        drawImage(field.image, 0, 0)
    }
}
