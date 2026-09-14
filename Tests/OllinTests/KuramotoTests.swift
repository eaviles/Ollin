import Testing
import Foundation
@testable import Ollin

/// Laws of the Kuramoto crowd, on the CPU: the transition at the critical
/// coupling, what the order parameter measures, determinism under a seed, the
/// uncoupled limit, the lagged locked state, and the ring.
struct KuramotoTests {

    @Test func aboveTheCriticalCouplingTheCrowdLocks() {
        // Four times the critical coupling: after twenty seconds the crowd is
        // nearly whole (the mean-field prototype reads r at 0.987).
        let sync = Kuramoto(count: 400, spread: 0.5, seed: 1)
        sync.coupling = 4 * sync.criticalCoupling
        for _ in 0 ..< 20 * 60 { sync.advance() }
        #expect(sync.coherence > 0.9)
    }

    @Test func belowItTheCrowdStaysScattered() {
        // A quarter of the critical coupling: r never rises past the finite-size
        // noise of four hundred phases (the prototype's peak is 0.08).
        let sync = Kuramoto(count: 400, spread: 0.5, seed: 1)
        sync.coupling = 0.25 * sync.criticalCoupling
        var peak = 0.0
        for _ in 0 ..< 20 * 60 {
            sync.advance()
            peak = max(peak, sync.coherence)
        }
        #expect(peak < 0.25)
    }

    @Test func theCoherenceIsTheLengthOfTheMeanUnitVector() {
        let sync = Kuramoto(count: 4, seed: 2)
        sync.phases = [0.3, 0.3, 0.3, 0.3]
        #expect(abs(sync.coherence - 1) < 1e-12)
        #expect(abs(sync.meanPhase - 0.3) < 1e-12)
        sync.phases = [0, .pi, 0, .pi]
        #expect(sync.coherence < 1e-12)
        sync.phases = [0, .pi / 2, 0, .pi / 2]
        #expect(abs(sync.coherence - 0.5.squareRoot()) < 1e-12)
        #expect(abs(sync.meanPhase - .pi / 4) < 1e-12)
    }

    @Test func theCriticalCouplingFollowsTheSpread() {
        let wide = Kuramoto(count: 10, spread: 0.5)
        #expect(abs(wide.criticalCoupling - 0.5 * (8 / Double.pi).squareRoot()) < 1e-12)
        #expect(Kuramoto(count: 10, spread: 0).criticalCoupling == 0)
    }

    @Test func runsReplayUnderASeedAndDifferUnderAnother() {
        let a = Kuramoto(count: 120, coupling: 1.5, seed: 3)
        let b = Kuramoto(count: 120, coupling: 1.5, seed: 3)
        let c = Kuramoto(count: 120, coupling: 1.5, seed: 4)
        for _ in 0 ..< 300 {
            a.advance()
            b.advance()
            c.advance()
        }
        #expect(a.phases == b.phases)
        #expect(a.frequencies == b.frequencies)
        #expect(a.phases != c.phases)
    }

    @Test func withNoCouplingEachRunsAtItsOwnPace() {
        // One second at coupling 0 turns every phase by exactly its frequency.
        let sync = Kuramoto(count: 50, coupling: 0, seed: 4)
        let start = sync.phases
        for _ in 0 ..< 60 { sync.advance() }
        for i in 0 ..< 50 {
            var expected = (start[i] + sync.frequencies[i]).truncatingRemainder(dividingBy: 2 * .pi)
            if expected < 0 { expected += 2 * .pi }
            #expect(abs(sync.phases[i] - expected) < 1e-9)
        }
    }

    @Test func theFrequenciesSpreadAsAsked() {
        let sync = Kuramoto(count: 4000, frequency: 2, spread: 0.5, seed: 9)
        let mean = sync.frequencies.reduce(0, +) / 4000
        let variance = sync.frequencies.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / 4000
        #expect(abs(mean - 2) < 0.03)
        #expect(abs(variance.squareRoot() - 0.5) < 0.03)
        #expect(Kuramoto(count: 8, spread: 0).frequencies.allSatisfy { $0 == 1 })
    }

    @Test func aLockedCrowdWithALagRunsSlow() {
        // Identical oscillators lock whole at any coupling; with a lag the locked
        // crowd advances at frequency - coupling * sin(lag) per second.
        let sync = Kuramoto(count: 100, coupling: 2, frequency: 1, spread: 0, lag: 0.3, seed: 5)
        for _ in 0 ..< 20 * 60 { sync.advance() }
        #expect(sync.coherence > 0.999)
        let before = sync.meanPhase
        for _ in 0 ..< 60 { sync.advance() }
        var moved = sync.meanPhase - before
        while moved < -.pi { moved += 2 * .pi }
        while moved > .pi { moved -= 2 * .pi }
        #expect(abs(moved - (1 - 2 * sin(0.3))) < 0.01)
    }

    @Test func aRingLocksItsNeighborsAndMayKeepATwist() {
        // Nearest neighbors on a ring lock locally (every neighbor pair within a
        // few degrees) while the ring as a whole can hold a twist, so the global
        // order stays low; the prototype reads 0.99 local against 0.1 to 0.3 global.
        let sync = Kuramoto(count: 200, coupling: 4, spread: 0, range: 2, seed: 6)
        for _ in 0 ..< 10 * 60 { sync.advance() }
        var local = 0.0
        for i in 0 ..< 200 { local += cos(sync.phases[(i + 1) % 200] - sync.phases[i]) }
        #expect(local / 200 > 0.95)
    }

    @Test func phasesStayWrapped() {
        let sync = Kuramoto(count: 80, coupling: 3, frequency: 4, seed: 7)
        for _ in 0 ..< 600 { sync.advance() }
        #expect(sync.phases.allSatisfy { $0 >= 0 && $0 < 2 * .pi })
        #expect(sync.count == 80)
    }
}
