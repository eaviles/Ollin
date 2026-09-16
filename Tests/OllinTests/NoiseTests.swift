import Testing
@testable import Ollin

/// Pure-math checks on the noise family: the looping (`loop:`) forms close
/// exactly and stay seeded, and `fbm` matches its hand-layered definition.
/// No GPU, so these run everywhere (including CI). Main-actor because noise
/// lives on the sketch.
@MainActor
@Suite
struct NoiseTests {

    @Test func loopClosesExactly() {
        let sketch = Sketch()
        sketch.noiseSeed(7)
        #expect(sketch.noise(loop: 1) == sketch.noise(loop: 0))
        #expect(sketch.noise(3.2, loop: 1) == sketch.noise(3.2, loop: 0))
        #expect(sketch.noise(3.2, 1.7, loop: 1) == sketch.noise(3.2, 1.7, loop: 0))
        #expect(sketch.signedNoise(3.2, 1.7, loop: 1) == sketch.signedNoise(3.2, 1.7, loop: 0))
        #expect(sketch.fbm(3.2, 1.7, loop: 1) == sketch.fbm(3.2, 1.7, loop: 0))
        #expect(sketch.noise(loop: 3) == sketch.noise(loop: 0), "any whole number of laps is home")
    }

    @Test func tilingClosesOnBothEdges() {
        let sketch = Sketch()
        sketch.noiseSeed(7)
        for t in [0.0, 0.13, 0.5, 0.87] {
            #expect(sketch.tilingNoise(0, t) == sketch.tilingNoise(1, t), "the left edge meets the right")
            #expect(sketch.tilingNoise(t, 0) == sketch.tilingNoise(t, 1), "the top edge meets the bottom")
            #expect(sketch.tilingFbm(0, t, octaves: 5) == sketch.tilingFbm(1, t, octaves: 5))
            #expect(sketch.tilingFbm(t, 0, octaves: 5) == sketch.tilingFbm(t, 1, octaves: 5))
            #expect(sketch.signedTilingNoise(0, t) == sketch.signedTilingNoise(1, t))
            #expect(sketch.signedTilingFbm(t, 0) == sketch.signedTilingFbm(t, 1))
        }
    }

    @Test func tilingIsContinuousAcrossTheJoin() {
        let sketch = Sketch()
        sketch.noiseSeed(7)
        // A field that merely *matches* at the edge can still kink there. The
        // step across the join must be no worse than a step of the same size
        // taken in the middle of the tile, which is what makes the repeat
        // invisible rather than merely continuous.
        let d = 0.002
        let across = abs(sketch.tilingFbm(1 - d, 0.4, detail: 4, octaves: 5)
                       - sketch.tilingFbm(d, 0.4, detail: 4, octaves: 5))
        let inside = abs(sketch.tilingFbm(0.5 - d, 0.4, detail: 4, octaves: 5)
                       - sketch.tilingFbm(0.5 + d, 0.4, detail: 4, octaves: 5))
        #expect(across < inside + 0.02, "the join is as smooth as the middle")
    }

    @Test func tilingActuallyVaries() {
        let sketch = Sketch()
        sketch.noiseSeed(7)
        // A constant field would pass every seam test above, so pin that the
        // tile carries real structure, and that a bigger radius carries more.
        func spread(_ detail: Double) -> Double {
            var lo = 1.0, hi = 0.0
            for i in 0 ..< 24 {
                for j in 0 ..< 24 {
                    let n = sketch.tilingFbm(Double(i) / 24, Double(j) / 24, detail: detail, octaves: 5)
                    lo = min(lo, n); hi = max(hi, n)
                }
            }
            return hi - lo
        }
        #expect(spread(4) > 0.2)
        #expect(spread(8) > spread(1), "a bigger tile tours more of the field")
    }

    @Test func tilingIsSeededAndDeterministic() {
        let a = Sketch(); a.noiseSeed(11)
        let b = Sketch(); b.noiseSeed(11)
        let c = Sketch(); c.noiseSeed(12)
        #expect(a.tilingFbm(0.3, 0.7) == b.tilingFbm(0.3, 0.7))
        #expect(a.tilingFbm(0.3, 0.7) != c.tilingFbm(0.3, 0.7))
    }

    @Test func loopIsContinuousAtTheSeam() {
        let sketch = Sketch()
        sketch.noiseSeed(7)
        let before = sketch.noise(2.0, 5.0, loop: 0.999)
        let after = sketch.noise(2.0, 5.0, loop: 0.001)
        #expect(abs(before - after) < 0.05, "the lap seam is a tiny step on the circle")
    }

    @Test func loopIsSeededAndDeterministic() {
        let a = Sketch()
        a.noiseSeed(11)
        let b = Sketch()
        b.noiseSeed(11)
        for i in 0..<32 {
            let p = Double(i) / 32
            #expect(a.noise(1.5, 2.5, loop: p) == b.noise(1.5, 2.5, loop: p))
            #expect(a.signedNoise(loop: p) == b.signedNoise(loop: p))
        }
    }

    /// Guards the 4D contrast calibration: a broad sweep should reach near
    /// both ends of `0...1`, like the 1D/2D/3D forms do.
    @Test func loopingNoiseFillsItsRange() {
        let sketch = Sketch()
        sketch.noiseSeed(3)
        var lo = 1.0, hi = 0.0
        for i in 0..<4096 {
            let p = Double(i) / 4096
            let n = sketch.noise(Double(i) * 0.37, Double(i) * 0.19, loop: p, radius: 1.4)
            #expect(n >= 0 && n <= 1)
            lo = Swift.min(lo, n)
            hi = Swift.max(hi, n)
        }
        #expect(lo < 0.12, "fills toward 0 (lo = \(lo))")
        #expect(hi > 0.88, "fills toward 1 (hi = \(hi))")
    }

    @Test func fbmSingleOctaveIsPlainNoise() {
        let sketch = Sketch()
        sketch.noiseSeed(5)
        #expect(sketch.fbm(1.3, octaves: 1) == sketch.noise(1.3))
        #expect(sketch.fbm(1.3, 4.2, octaves: 1) == sketch.noise(1.3, 4.2))
        #expect(sketch.fbm(1.3, 4.2, 0.7, octaves: 1) == sketch.noise(1.3, 4.2, 0.7))
    }

    @Test func fbmMatchesTheHandLayeredSum() {
        let sketch = Sketch()
        sketch.noiseSeed(5)
        let x = 2.4, y = 0.9
        let byHand = (sketch.noise(x, y) * 1.0 + sketch.noise(x * 2, y * 2) * 0.5) / 1.5
        #expect(abs(sketch.fbm(x, y, octaves: 2) - byHand) < 1e-12)
    }

    @Test func fbmStaysInRangeAndSignedMirrors() {
        let sketch = Sketch()
        sketch.noiseSeed(9)
        for i in 0..<512 {
            let v = sketch.fbm(Double(i) * 0.13, Double(i) * 0.07)
            #expect(v >= 0 && v <= 1)
            let s = sketch.signedFbm(Double(i) * 0.13, Double(i) * 0.07)
            #expect(abs(s - (v * 2 - 1)) < 1e-12)
        }
    }
}

/// The noise-variant family: simplex, Worley, ridged, turbulence, and warped
/// fbm. Same rules as the classic field: seeded, deterministic, range-honest.
@MainActor
@Suite
struct NoiseVariantTests {

    @Test func simplexIsSeededAndDeterministic() {
        let a = Sketch()
        a.noiseSeed(11)
        let b = Sketch()
        b.noiseSeed(11)
        let c = Sketch()
        c.noiseSeed(12)
        var differs = false
        for i in 0..<64 {
            let x = Double(i) * 0.37, y = Double(i) * 0.19
            #expect(a.simplexNoise(x, y) == b.simplexNoise(x, y))
            #expect(a.simplexNoise(x, y, 1.5) == b.simplexNoise(x, y, 1.5))
            if a.simplexNoise(x, y) != c.simplexNoise(x, y) { differs = true }
        }
        #expect(differs, "a different seed reads a different field")
    }

    /// Guards the contrast calibration: a broad sweep should reach near both
    /// ends of `0...1` in 2D and 3D, like the classic field does.
    @Test func simplexFillsItsRange() {
        let sketch = Sketch()
        sketch.noiseSeed(3)
        var lo2 = 1.0, hi2 = 0.0, lo3 = 1.0, hi3 = 0.0
        for i in 0..<4096 {
            let x = Double(i) * 0.173, y = Double(i % 71) * 0.291
            let n2 = sketch.simplexNoise(x, y)
            let n3 = sketch.simplexNoise(x, y, Double(i % 53) * 0.117)
            #expect(n2 >= 0 && n2 <= 1)
            #expect(n3 >= 0 && n3 <= 1)
            lo2 = Swift.min(lo2, n2); hi2 = Swift.max(hi2, n2)
            lo3 = Swift.min(lo3, n3); hi3 = Swift.max(hi3, n3)
        }
        #expect(lo2 < 0.05 && hi2 > 0.95, "2D fills its range (\(lo2)...\(hi2))")
        #expect(lo3 < 0.05 && hi3 > 0.95, "3D fills its range (\(lo3)...\(hi3))")
        #expect(abs(sketch.signedSimplexNoise(1.7, 2.9) - (sketch.simplexNoise(1.7, 2.9) * 2 - 1)) < 1e-12,
                "the signed form mirrors the unsigned one")
    }

    @Test func worleyReadingsAreOrderedAndSeeded() {
        let a = Sketch()
        a.noiseSeed(5)
        let b = Sketch()
        b.noiseSeed(5)
        for i in 0..<128 {
            let x = Double(i) * 0.83, y = Double(i) * 0.41
            let f1 = a.worley(x, y), f2 = a.worley(x, y, feature: .second)
            #expect(f1 >= 0)
            #expect(f2 >= f1, "the second-nearest point is never nearer")
            #expect(a.worley(x, y, feature: .border) == f2 - f1)
            #expect(a.worley(x, y) == b.worley(x, y), "seeded: same seed, same cells")
            let g1 = a.worley(x, y, 0.7), g2 = a.worley(x, y, 0.7, feature: .second)
            #expect(g2 >= g1)
        }
        #expect(a.worley(1.3, 2.6, jitter: 2.5) == a.worley(1.3, 2.6), "jitter clamps to 1")
    }

    /// With no jitter every feature point sits at its cell center, so the
    /// distances are pure geometry.
    @Test func worleyZeroJitterIsARegularGrid() {
        let sketch = Sketch()
        sketch.noiseSeed(9)
        #expect(abs(sketch.worley(0.5, 0.5, jitter: 0)) < 1e-12)
        #expect(abs(sketch.worley(10.5, 3.5, 7.5, jitter: 0)) < 1e-12)
        #expect(abs(sketch.worley(0.0, 0.5, jitter: 0) - 0.5) < 1e-12)
    }

    @Test func ridgedAndTurbulenceStayInRange() {
        let sketch = Sketch()
        sketch.noiseSeed(4)
        var rHi = 0.0, tLo = 1.0
        for i in 0..<2048 {
            let x = Double(i) * 0.211, y = Double(i % 97) * 0.173
            let r = sketch.ridgedFbm(x, y)
            let t = sketch.turbulence(x, y)
            #expect(r >= 0 && r <= 1)
            #expect(t >= 0 && t <= 1)
            rHi = Swift.max(rHi, r)
            tLo = Swift.min(tLo, t)
        }
        #expect(rHi > 0.8, "ridge lines reach bright (\(rHi))")
        #expect(tLo < 0.1, "turbulence creases reach dark (\(tLo))")
    }

    /// One octave reduces each variant to its per-octave definition over the
    /// classic signed field.
    @Test func singleOctaveMatchesTheDefinition() {
        let sketch = Sketch()
        sketch.noiseSeed(8)
        for i in 0..<32 {
            let x = Double(i) * 0.37, y = Double(i) * 0.53
            let folded = 1 - abs(sketch.signedNoise(x, y))
            #expect(abs(sketch.ridgedFbm(x, y, octaves: 1) - folded * folded) < 1e-12)
            #expect(abs(sketch.turbulence(x, y, octaves: 1) - abs(sketch.signedNoise(x, y))) < 1e-12)
        }
    }

    @Test func warpZeroIsPlainFbm() {
        let sketch = Sketch()
        sketch.noiseSeed(2)
        for i in 0..<32 {
            let x = Double(i) * 0.31, y = Double(i) * 0.47
            #expect(sketch.warpedFbm(x, y, warp: 0) == sketch.fbm(x, y))
        }
    }

    @Test func variantLoopsCloseExactly() {
        let sketch = Sketch()
        sketch.noiseSeed(7)
        #expect(sketch.ridgedFbm(3.2, 1.7, loop: 1) == sketch.ridgedFbm(3.2, 1.7, loop: 0))
        #expect(sketch.turbulence(3.2, 1.7, loop: 1) == sketch.turbulence(3.2, 1.7, loop: 0))
        #expect(sketch.warpedFbm(3.2, 1.7, loop: 1) == sketch.warpedFbm(3.2, 1.7, loop: 0))
    }
}

/// The curl forms: the 2D curl is the slope of the field turned a quarter turn,
/// the 3D curl is the curl of three offset copies of it, both worked out in
/// closed form, so both are checked against differences taken through the
/// public field and against the one law a curl has to keep: no divergence.
@MainActor
@Suite
struct CurlNoiseTests {

    /// Points where the stencil stays clear of the calibration's clip, since
    /// the field's slope jumps there and no difference can be trusted across it.
    private func clearOfTheClip(_ values: [Double]) -> Bool {
        values.allSatisfy { $0 > 0.02 && $0 < 0.98 }
    }

    /// The 2D curl matches central differences of `noise(x, y)`.
    @Test func curl2DIsTheSlopeOfTheField() {
        let sketch = Sketch()
        sketch.noiseSeed(7)
        let eps = 1e-4
        var checked = 0
        for i in 0 ..< 200 {
            let x = Double(i) * 0.731 + 0.37, y = Double(i % 37) * 0.529 + 0.11
            let samples = [sketch.noise(x + eps, y), sketch.noise(x - eps, y),
                           sketch.noise(x, y + eps), sketch.noise(x, y - eps)]
            guard clearOfTheClip(samples) else { continue }
            let dfdx = (samples[0] - samples[1]) / (2 * eps)
            let dfdy = (samples[2] - samples[3]) / (2 * eps)
            let curl = sketch.curlNoise(x, y)
            #expect(abs(curl.x - dfdy) < 1e-6 && abs(curl.y + dfdx) < 1e-6,
                    "at (\(x), \(y)): \(curl) vs (\(dfdy), \(-dfdx))")
            checked += 1
        }
        #expect(checked > 150)
    }

    /// The 3D curl matches central differences of the same three offset
    /// copies of `noise(x, y, z)`, which pins the closed-form gradient.
    @Test func curl3DIsTheCurlOfThreeOffsetFields() {
        let sketch = Sketch()
        sketch.noiseSeed(7)
        let eps = 1e-4
        func potential(_ x: Double, _ y: Double, _ z: Double) -> [Double] {
            [sketch.noise(x, y, z),
             sketch.noise(x + 31.4, y - 47.2, z + 12.9),
             sketch.noise(x - 71.1, y + 23.6, z - 58.3)]
        }
        var checked = 0
        for i in 0 ..< 200 {
            let x = Double(i) * 0.613 + 0.29, y = Double(i % 41) * 0.457 + 0.83, z = Double(i % 23) * 0.377 + 0.51
            let xp = potential(x + eps, y, z), xm = potential(x - eps, y, z)
            let yp = potential(x, y + eps, z), ym = potential(x, y - eps, z)
            let zp = potential(x, y, z + eps), zm = potential(x, y, z - eps)
            guard clearOfTheClip(xp + xm + yp + ym + zp + zm) else { continue }
            let expected = Vector3((yp[2] - ym[2] - zp[1] + zm[1]) / (2 * eps),
                                   (zp[0] - zm[0] - xp[2] + xm[2]) / (2 * eps),
                                   (xp[1] - xm[1] - yp[0] + ym[0]) / (2 * eps))
            let curl = sketch.curlNoise(x, y, z)
            #expect(curl.distance(to: expected) < 1e-6, "at (\(x), \(y), \(z)): \(curl) vs \(expected)")
            checked += 1
        }
        #expect(checked > 100)
    }

    /// A curl has no divergence: the flow neither gathers nor drains anywhere
    /// the field is smooth.
    @Test func curl3DIsDivergenceFree() {
        let sketch = Sketch()
        sketch.noiseSeed(11)
        let eps = 1e-4
        var checked = 0, largest = 0.0
        for i in 0 ..< 200 {
            let p = Vector3(Double(i) * 0.371 + 0.17, Double(i % 29) * 0.611 + 0.43, Double(i % 17) * 0.293 + 0.77)
            // Stay clear of the clip on every copy the curl reads.
            var values: [Double] = []
            for offset in [Vector3.zero, Vector3(31.4, -47.2, 12.9), Vector3(-71.1, 23.6, -58.3)] {
                let q = p + offset
                values.append(sketch.noise(q.x, q.y, q.z))
            }
            guard clearOfTheClip(values) else { continue }
            let dx = sketch.curlNoise(p + Vector3(eps, 0, 0)).x - sketch.curlNoise(p - Vector3(eps, 0, 0)).x
            let dy = sketch.curlNoise(p + Vector3(0, eps, 0)).y - sketch.curlNoise(p - Vector3(0, eps, 0)).y
            let dz = sketch.curlNoise(p + Vector3(0, 0, eps)).z - sketch.curlNoise(p - Vector3(0, 0, eps)).z
            let divergence = (dx + dy + dz) / (2 * eps)
            largest = max(largest, abs(divergence))
            checked += 1
        }
        #expect(checked > 100)
        #expect(largest < 1e-5, "largest divergence \(largest)")
    }

    /// The field is seeded like every other, and the vector forms are the
    /// scalar forms.
    @Test func curlIsSeededAndTheVectorFormsMatch() {
        let a = Sketch(); a.noiseSeed(3)
        let b = Sketch(); b.noiseSeed(3)
        let c = Sketch(); c.noiseSeed(4)
        var differs = false
        for i in 0 ..< 32 {
            let p = Vector3(Double(i) * 0.41, Double(i) * 0.23 + 1, Double(i) * 0.17 + 2)
            #expect(a.curlNoise(p) == b.curlNoise(p))
            #expect(a.curlNoise(p) == a.curlNoise(p.x, p.y, p.z))
            #expect(a.curlNoise(p.xy) == a.curlNoise(p.x, p.y))
            if a.curlNoise(p) != c.curlNoise(p) { differs = true }
        }
        #expect(differs, "a different seed reads a different flow")
    }

    /// The 3D flow has real size in every axis: not a 2D field in disguise,
    /// and not normalized.
    @Test func curl3DMovesInEveryAxis() {
        let sketch = Sketch()
        sketch.noiseSeed(5)
        var sum = Vector3.zero, lengths: [Double] = []
        for i in 0 ..< 512 {
            let p = Vector3(Double(i) * 0.137, Double(i % 61) * 0.211, Double(i % 47) * 0.173)
            let v = sketch.curlNoise(p)
            sum += Vector3(abs(v.x), abs(v.y), abs(v.z))
            lengths.append(v.length)
        }
        #expect(sum.x > 10 && sum.y > 10 && sum.z > 10, "every axis carries flow: \(sum)")
        let spread = lengths.max()! - lengths.min()!
        #expect(spread > 0.5, "the magnitude varies, so it is not normalized (spread \(spread))")
    }
}
