import Testing
import Foundation
@testable import Ollin

/// The three-dimensional looping forms (`noise(_:_:_:loop:radius:)` and its
/// family) and the five-axis lattice under them: every lap closes exactly, the
/// lattice hashes and blends its 32 corners the way a plain corner-by-corner
/// sum does, and the field spreads like the 3D one a sketch already knows.
/// The math reads the `NoiseFields` value, so it stays off the main actor;
/// the sketch's forwarders are checked against it in their own suite.
struct LoopingNoise3DTests {

    @Test func everyFormClosesItsLapExactly() {
        let sketch = NoiseFields(seed: 0)
        let (x, y, z) = (3.2, 1.7, -4.4)
        for laps in [1.0, 3.0] {
            #expect(sketch.noise(x, y, z, loop: laps) == sketch.noise(x, y, z, loop: 0))
            #expect(sketch.signedNoise(x, y, z, loop: laps) == sketch.signedNoise(x, y, z, loop: 0))
            #expect(sketch.fbm(x, y, z, loop: laps) == sketch.fbm(x, y, z, loop: 0))
            #expect(sketch.signedFbm(x, y, z, loop: laps) == sketch.signedFbm(x, y, z, loop: 0))
            #expect(sketch.ridgedFbm(x, y, z, loop: laps) == sketch.ridgedFbm(x, y, z, loop: 0))
            #expect(sketch.turbulence(x, y, z, loop: laps) == sketch.turbulence(x, y, z, loop: 0))
        }
    }

    @Test func theLapIsContinuousAtItsSeam() {
        let sketch = NoiseFields(seed: 0)
        var worst = 0.0
        for i in 0..<200 {
            let p = (Double(i) * 0.61, Double(i) * 0.37, Double(i) * 0.23)
            let before = sketch.noise(p.0, p.1, p.2, loop: 0.9999)
            let after = sketch.noise(p.0, p.1, p.2, loop: 0.0001)
            worst = max(worst, abs(before - after))
        }
        #expect(worst < 0.01, "a lap's last step and its first are neighbors: \(worst)")
    }

    @Test func aSeedReproducesTheVolume() {
        let a = NoiseFields(seed: 42)
        var b = NoiseFields(seed: 42)
        for k in 0..<50 {
            let t = Double(k) / 50
            #expect(a.noise(1.5, 2.5, 0.5, loop: t) == b.noise(1.5, 2.5, 0.5, loop: t))
        }
        b = NoiseFields(seed: 43)
        let differs = (0..<50).contains { k in
            a.noise(1.5, 2.5, Double(k) * 0.3, loop: 0.25) != b.noise(1.5, 2.5, Double(k) * 0.3, loop: 0.25)
        }
        #expect(differs, "another seed is another volume")
    }

    @Test func theVolumeVariesInEveryAxisAndAroundTheLap() {
        let sketch = NoiseFields(seed: 0)
        let base = sketch.noise(0.3, 0.4, 0.5, loop: 0)
        #expect(sketch.noise(1.3, 0.4, 0.5, loop: 0) != base)
        #expect(sketch.noise(0.3, 1.4, 0.5, loop: 0) != base)
        #expect(sketch.noise(0.3, 0.4, 1.5, loop: 0) != base)
        #expect(sketch.noise(0.3, 0.4, 0.5, loop: 0.5) != base)
    }

    /// A gradient lattice is zero at its own lattice points, whatever the
    /// gradients are: every corner's offset there is zero or the corner's
    /// weight is.
    @Test func theLatticeIsZeroAtItsPoints() {
        let field = PerlinNoise(seed: 7)
        for k in 0..<64 {
            let p = (Double(k % 4), Double((k / 4) % 4), Double(k % 3) - 1, Double(k % 5), -Double(k % 7))
            #expect(field.signedValue(p.0, p.1, p.2, p.3, p.4) == 0)
        }
    }

    /// The shared-prefix hashing and the axis-at-a-time blend against the plain
    /// definition: every corner hashed through the table on its own, weighted
    /// by the product of its five fades, and summed.
    @Test func theLatticeMatchesTheCornerByCornerSum() {
        let seed: UInt64 = 2026
        let field = PerlinNoise(seed: seed)
        let perm = PerlinNoise.permutation(seed: seed)
        func fade(_ t: Double) -> Double { t * t * t * (t * (t * 6 - 15) + 10) }
        func reference(_ p: [Double]) -> Double {
            let cells = p.map { PerlinNoise.cell($0) }
            let f = p.map { $0 - floor($0) }
            var sum = 0.0
            for k in 0..<32 {
                let bits = (0..<5).map { (k >> $0) & 1 }
                var h = perm[cells[0] + bits[0]]
                for axis in 1..<5 { h = perm[h + cells[axis] + bits[axis]] }
                let skip = ((h & 255) * 5) >> 8
                var dot = 0.0, bit = 0
                for axis in 0..<5 where axis != skip {
                    let d = f[axis] - Double(bits[axis])
                    dot += (h >> bit) & 1 == 0 ? d : -d
                    bit += 1
                }
                var weight = 1.0
                for axis in 0..<5 { weight *= bits[axis] == 1 ? fade(f[axis]) : 1 - fade(f[axis]) }
                sum += dot * weight
            }
            return max(-1, min(1, sum * PerlinNoise.gain5))
        }
        var rng = SplitMix64(seed: 5)
        var worst = 0.0
        for _ in 0..<2_000 {
            let p = (0..<5).map { _ in Double(rng.next() % 100_000) / 1_000 - 50 }
            worst = max(worst, abs(field.signedValue(p[0], p[1], p[2], p[3], p[4]) - reference(p)))
        }
        #expect(worst < 1e-12, "the lattice and its definition agree: \(worst)")
    }

    /// Each of the five zero axes is picked by 51 or 52 of the table's 256
    /// values, so no axis is favored by more than one value in fifty.
    @Test func theGradientSetIsBalanced() {
        var counts = [Int](repeating: 0, count: 5)
        for h in 0..<256 { counts[(h * 5) >> 8] += 1 }
        #expect(counts.min()! >= 51 && counts.max()! <= 52, "\(counts)")
    }

    /// The gain pinned against the 3D field's spread: a sketch that moves from
    /// `noise(x, y, z)` to the looping form keeps its contrast.
    @Test func theLoopingVolumeSpreadsLikeTheVolume() {
        let sketch = NoiseFields(seed: 0)
        var rng = SplitMix64(seed: 99)
        func u() -> Double { Double(rng.next() % 1_000_000) / 1_000_000 * 40 - 20 }
        func spread(_ values: [Double]) -> (sd: Double, clipped: Double) {
            let mean = values.reduce(0, +) / Double(values.count)
            let sd = (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)).squareRoot()
            let clipped = Double(values.filter { abs($0) >= 1 }.count) / Double(values.count)
            return (sd, clipped)
        }
        var flat: [Double] = [], looping: [Double] = []
        for _ in 0..<100_000 {
            let (x, y, z) = (u(), u(), u())
            flat.append(sketch.signedNoise(x, y, z))
            looping.append(sketch.signedNoise(x, y, z, loop: Double(rng.next() % 1000) / 1000, radius: 3))
        }
        let a = spread(flat), b = spread(looping)
        #expect(abs(a.sd - b.sd) < 0.02, "spread \(b.sd) against the volume's \(a.sd)")
        #expect(abs(a.clipped - b.clipped) < 0.02, "clipped \(b.clipped) against \(a.clipped)")
    }

    /// One octave of the layered forms is the plain looping field.
    @Test func oneOctaveIsTheField() {
        let sketch = NoiseFields(seed: 0)
        let (x, y, z, t) = (0.7, -1.2, 2.9, 0.31)
        #expect(sketch.fbm(x, y, z, loop: t, octaves: 1) == sketch.noise(x, y, z, loop: t))
        #expect(abs(sketch.turbulence(x, y, z, loop: t, octaves: 1)
                    - abs(sketch.signedNoise(x, y, z, loop: t))) < 1e-15)
    }
}

/// The bare calls on a sketch read the same fields as the value seeded alike.
@MainActor
@Suite
struct LoopingNoise3DSketchTests {

    @Test func theSketchForwardsEveryForm() {
        let sketch = Sketch()
        sketch.noiseSeed(11)
        let fields = NoiseFields(seed: 11)
        let (x, y, z, t) = (0.4, 1.9, -0.8, 0.62)
        #expect(sketch.noise(x, y, z, loop: t, radius: 2) == fields.noise(x, y, z, loop: t, radius: 2))
        #expect(sketch.signedNoise(x, y, z, loop: t) == fields.signedNoise(x, y, z, loop: t))
        #expect(sketch.fbm(x, y, z, loop: t, octaves: 3) == fields.fbm(x, y, z, loop: t, octaves: 3))
        #expect(sketch.signedFbm(x, y, z, loop: t) == fields.signedFbm(x, y, z, loop: t))
        #expect(sketch.ridgedFbm(x, y, z, loop: t) == fields.ridgedFbm(x, y, z, loop: t))
        #expect(sketch.turbulence(x, y, z, loop: t) == fields.turbulence(x, y, z, loop: t))
    }
}
