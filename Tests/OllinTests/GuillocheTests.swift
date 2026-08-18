import Foundation
import Ollin
import Testing

/// Guilloche invariants: the rings sit on their bases, each ring waves its
/// rosette's bump count, the twist is a pure rotation of the wave, and
/// stacked rosettes superpose.
@Suite struct GuillocheTests {

    /// Each ring's mean radius is exactly its base (a whole number of waves
    /// averages to zero over the even sampling), the bases run evenly from
    /// inner to outer, and no point leaves the amplitude band.
    @Test func ringsSitOnTheirBases() {
        let rings = guilloche(rings: 5, innerRadius: 100, outerRadius: 300,
                              bumps: 9, amplitude: 12, samples: 360)
        #expect(rings.count == 5)
        for (k, ring) in rings.enumerated() {
            let base = 100 + 50 * Double(k)
            let radii = ring.points.map(\.length)
            let mean = radii.reduce(0, +) / Double(radii.count)
            #expect(abs(mean - base) < 1e-9)
            #expect(radii.allSatisfy { $0 > base - 12 - 1e-9 && $0 < base + 12 + 1e-9 })
            #expect(ring.isClosed)
        }
    }

    /// A ring waves exactly `bumps` times: counting its local radius maxima
    /// around the closed curve gives the bump count.
    @Test func aRingWavesItsBumpCount() {
        let ring = guilloche(rings: 1, innerRadius: 200, outerRadius: 200,
                             bumps: 7, amplitude: 15, samples: 700)[0]
        let radii = ring.points.map(\.length)
        let n = radii.count
        var maxima = 0
        for i in 0..<n where radii[i] > radii[(i + n - 1) % n] && radii[i] > radii[(i + 1) % n] {
            maxima += 1
        }
        #expect(maxima == 7)
    }

    /// The twist rotates the wave without reshaping it: with the twist a
    /// whole number of sample steps, ring 1's wave is ring 0's wave shifted
    /// by exactly that many samples.
    @Test func twistIsAPureRotation() {
        let count = 360
        let step = 5
        let rings = guilloche(rings: 2, innerRadius: 150, outerRadius: 250,
                              rosettes: [Rosette(bumps: 11, amplitude: 20, phase: 0.4)],
                              twist: .tau / Double(count) * Double(step),
                              samples: count)
        let wave0 = rings[0].points.map { $0.length - 150 }
        let wave1 = rings[1].points.map { $0.length - 250 }
        for i in 0..<count {
            #expect(abs(wave1[i] - wave0[(i + step) % count]) < 1e-9)
        }
    }

    /// Stacked rosettes superpose: the two-cam guilloche is the sum of the
    /// two one-cam waves over the same base.
    @Test func rosettesSuperpose() {
        let coarse = Rosette(bumps: 6, amplitude: 24)
        let fine = Rosette(bumps: 30, amplitude: 5, phase: 1.1)
        let both = guilloche(rings: 1, innerRadius: 220, outerRadius: 220,
                             rosettes: [coarse, fine], samples: 720)[0]
        let a = guilloche(rings: 1, innerRadius: 220, outerRadius: 220,
                          rosettes: [coarse], samples: 720)[0]
        let b = guilloche(rings: 1, innerRadius: 220, outerRadius: 220,
                          rosettes: [fine], samples: 720)[0]
        for i in 0..<720 {
            let sum = (a.points[i].length - 220) + (b.points[i].length - 220) + 220
            #expect(abs(both.points[i].length - sum) < 1e-9)
        }
    }

    /// Degenerate calls answer plainly: no rings is empty, one ring sits on
    /// the inner radius.
    @Test func degenerateCallsAreCalm() {
        #expect(guilloche(rings: 0, innerRadius: 10, outerRadius: 20,
                          bumps: 5, amplitude: 2).isEmpty)
        let single = guilloche(rings: 1, innerRadius: 80, outerRadius: 999,
                               bumps: 5, amplitude: 0, samples: 90)[0]
        #expect(single.points.allSatisfy { abs($0.length - 80) < 1e-9 })
    }
}
