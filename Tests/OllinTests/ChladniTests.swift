import Ollin
import Testing

/// Pure-CPU checks on the `chladni` standing-wave field: the closed form's
/// exact values, the symmetries the default amplitudes promise (antisymmetry
/// across the diagonal, negation under a mode swap, cancellation at m == n),
/// the normalized range, and the mirrored periodic extension. No GPU.
@Suite
struct ChladniTests {

    @Test func matchesTheClosedFormAtAKnownPoint() {
        // At (0.25, 0.5) with m 5, n 2 the first term vanishes
        // (cos(2π·0.25) = 0) and the second is -cos(1.25π)·cos(π) = -√2/2,
        // normalized by the amplitude span 2.
        let value = chladni(0.25, 0.5, m: 5, n: 2)
        #expect(abs(value - (-2.0.squareRoot() / 4)) < 1e-12)
    }

    @Test func diagonalIsAlwaysNodal() {
        for i in 0 ... 20 {
            let t = Double(i) / 20
            #expect(abs(chladni(t, t, m: 7, n: 3)) < 1e-12)
        }
    }

    @Test func antisymmetricAcrossTheDiagonal() {
        for (x, y) in [(0.1, 0.7), (0.33, 0.9), (0.5, 0.05), (0.81, 0.42)] {
            let forward = chladni(x, y, m: 6, n: 2)
            let mirrored = chladni(y, x, m: 6, n: 2)
            #expect(abs(forward + mirrored) < 1e-12)
        }
    }

    @Test func swappingModesNegatesTheField() {
        let a = chladni(0.3, 0.8, m: 5, n: 2)
        let b = chladni(0.3, 0.8, m: 2, n: 5)
        #expect(abs(a + b) < 1e-12)
    }

    @Test func equalModesCancelEverywhere() {
        for (x, y) in [(0.2, 0.6), (0.45, 0.1), (0.9, 0.9)] {
            #expect(chladni(x, y, m: 4, n: 4) == 0)
        }
    }

    @Test func staysInTheNormalizedRange() {
        for i in 0 ..< 40 {
            for j in 0 ..< 40 {
                let value = chladni(Double(i) / 39, Double(j) / 39, m: 8, n: 3)
                #expect(value >= -1 && value <= 1)
            }
        }
    }

    @Test func extendsAsMirroredPlates() {
        // cos is even and 2-periodic in these units, so the field repeats
        // every 2 plate widths and mirrors across each plate edge.
        let inside = chladni(0.3, 0.55, m: 5, n: 2)
        #expect(abs(chladni(2.3, 0.55, m: 5, n: 2) - inside) < 1e-12)
        #expect(abs(chladni(-0.3, 0.55, m: 5, n: 2) - inside) < 1e-12)
    }

    @Test func amplitudesWeightTheTwoModes() {
        // b: 0 leaves the bare first mode, normalized by |a|.
        let bare = chladni(0.2, 0.7, m: 5, n: 2, a: 2, b: 0)
        let expected = cos(2 * .pi * 0.2) * cos(5 * .pi * 0.7)
        #expect(abs(bare - expected) < 1e-12)
        // A zero amplitude span defines the field as flat.
        #expect(chladni(0.2, 0.7, m: 5, n: 2, a: 0, b: 0) == 0)
    }
}
