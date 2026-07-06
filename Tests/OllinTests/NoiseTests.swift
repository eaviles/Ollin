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
