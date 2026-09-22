import Testing
import Foundation
@testable import Ollin

/// Invariants of the Kuramoto crowd, on the CPU: the transition at the critical
/// coupling, what the order parameter measures, determinism under a seed, the
/// uncoupled limit, the lagged locked state, the ring, the lattice and the graph,
/// the local order parameter, and the layers of one site.
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

    // MARK: - The lattice and the graph

    @Test func aGraphOfTheRingsOwnListsStepsExactlyAsTheRingDoes() {
        // The graph path and the ring path are one rule: hand the ring's own lists
        // to a graph crowd with the same seed and every phase agrees to the bit.
        let ring = Kuramoto(count: 60, coupling: 3, spread: 0.3, lag: 0.2, range: 2, seed: 11)
        let lists = ring.neighbors!
        #expect(lists.count == 60)
        #expect(lists.allSatisfy { $0.count == 4 })
        let graph = Kuramoto(neighbors: lists, coupling: 3, spread: 0.3, lag: 0.2, seed: 11)
        #expect(graph.phases == ring.phases)
        for _ in 0 ..< 120 {
            ring.advance()
            graph.advance()
        }
        #expect(graph.phases == ring.phases)
    }

    @Test func aLatticeAtRangeZeroIsTheMeanField() {
        // The same seed deals the same phases whether the crowd is a lattice or a
        // count, and at range 0 the lattice listens to everyone, so both step alike.
        let field = Kuramoto(count: 48, coupling: 2, seed: 5)
        let lattice = Kuramoto(columns: 8, rows: 6, coupling: 2, range: 0, seed: 5)
        #expect(lattice.neighbors == nil)
        for _ in 0 ..< 90 {
            field.advance()
            lattice.advance()
        }
        #expect(lattice.phases == field.phases)
    }

    @Test func squareNeighborhoodsCountAsTheyShould() {
        let four = Kuramoto.Lattice(columns: 5, rows: 4, layout: .square(.vonNeumann))
        let inner = four.index(column: 2, row: 2)
        #expect(four.neighbors(of: inner, within: 1) ==
                [four.index(column: 2, row: 1), four.index(column: 1, row: 2),
                 four.index(column: 3, row: 2), four.index(column: 2, row: 3)])
        #expect(four.neighbors(of: four.index(column: 0, row: 0), within: 1).count == 2)
        #expect(four.neighbors(of: inner, within: 2).count == 11)   // a diamond of 12 cut by the bottom rim
        let eight = Kuramoto.Lattice(columns: 5, rows: 4, layout: .square(.moore))
        #expect(eight.neighbors(of: inner, within: 1).count == 8)
        #expect(eight.neighbors(of: eight.index(column: 0, row: 0), within: 1).count == 3)
        // On the torus every site has the full set, corners included.
        let torus = Kuramoto.Lattice(columns: 5, rows: 4, layout: .square(.moore), wraps: true)
        #expect((0 ..< torus.count).allSatisfy { torus.neighbors(of: $0, within: 1).count == 8 })
        let corner = torus.neighbors(of: 0, within: 1)
        #expect(corner.contains(torus.index(column: 4, row: 3)))
        // A lattice wired in array order would couple along rows only; here the
        // cell below is a neighbor and the cell two columns over is not.
        #expect(four.neighbors(of: 0, within: 1).contains(four.index(column: 0, row: 1)))
        #expect(!four.neighbors(of: 0, within: 1).contains(2))
    }

    @Test func theHexLatticeSharesTheHexGridsAddressing() {
        // The crowd's hex neighbors within a range are exactly the HexGrid cells at
        // that hex distance or less, for every cell, so a sketch that draws
        // `hexGrid(columns:rows:)[i]` for site i couples what it draws.
        let grid = HexGrid(in: Rectangle(x: 0, y: 0, width: 900, height: 700), columns: 9, rows: 7)
        let lattice = Kuramoto.Lattice(columns: 9, rows: 7, layout: .hex)
        for range in 1 ... 3 {
            for (i, cell) in grid.enumerated() {
                let expected = grid.enumerated()
                    .filter { $0.offset != i && grid.distance(from: cell, to: $0.element) <= range }
                    .map(\.offset)
                #expect(lattice.neighbors(of: i, within: range) == expected)
            }
        }
        let inner = lattice.index(column: 4, row: 3)
        #expect(lattice.neighbors(of: inner, within: 1).count == 6)
        #expect(lattice.neighbors(of: inner, within: 2).count == 18)
        // A hex torus with an even row count gives every site its six.
        let torus = Kuramoto.Lattice(columns: 8, rows: 6, layout: .hex, wraps: true)
        #expect((0 ..< torus.count).allSatisfy { torus.neighbors(of: $0, within: 1).count == 6 })
    }

    @Test func aLatticeLocksInPatchesAndTheLocalOrderSaysWhere() {
        // Identical oscillators on a square lattice at nearest neighbors lock in
        // patches: most sites agree with their neighbors, so the local order
        // parameter reads near 1 over most of the field, while the defects between
        // patches keep the crowd as a whole well short of that (the prototype
        // reads a local mean of 0.94 against a global r far below it).
        let sync = Kuramoto(columns: 20, rows: 20, coupling: 4, spread: 0, range: 1, seed: 8)
        for _ in 0 ..< 10 * 60 { sync.advance() }
        let local = sync.localCoherence
        #expect(local.count == 400)
        let mean = local.reduce(0, +) / 400
        #expect(mean > 0.9)
        #expect(local.filter { $0 > 0.95 }.count > 280)
        #expect(sync.coherence < mean - 0.1)
        // And it is what it says: the mean unit vector over the site and its list.
        let lists = sync.neighbors!
        for s in [0, 21, 210, 399] {
            var x = cos(sync.phases[s]), y = sin(sync.phases[s])
            for j in lists[s] { x += cos(sync.phases[j]); y += sin(sync.phases[j]) }
            let r = (x * x + y * y).squareRoot() / Double(lists[s].count + 1)
            #expect(abs(local[s] - r) < 1e-12)
        }
    }

    @Test func theLocalOrderIsTheGlobalOneUnderTheMeanFieldAndOneForALoner() {
        let field = Kuramoto(count: 30, seed: 2)
        for _ in 0 ..< 30 { field.advance() }
        #expect(field.localCoherence.allSatisfy { abs($0 - field.coherence) < 1e-12 })
        let loner = Kuramoto(neighbors: [[], [0]], seed: 3)
        loner.phases = [0.4, 2.9]
        #expect(loner.localCoherence[0] == 1)
        #expect(abs(loner.localCoherence[1] - abs(cos((2.9 - 0.4) / 2))) < 1e-12)
    }

    @Test func aGraphMayBeHandedOverAndTakenBack() {
        let sync = Kuramoto(columns: 4, rows: 3, coupling: 2, range: 1, seed: 1)
        #expect(sync.neighbors?.count == 12)
        #expect(sync.neighbors?[5].count == 4)
        sync.neighbors = (0 ..< 12).map { [($0 + 1) % 12] }
        #expect(sync.neighbors?[5] == [6])
        sync.range = 2
        #expect(sync.neighbors?[5] == [6])   // the graph holds whatever range says
        sync.neighbors = nil
        #expect(sync.neighbors?[5].count == 9)   // back on the lattice, now two rings: a diamond of 12 cut by the top and bottom rims
    }

    @Test func theRangeOnALatticeChangesWhatItListensTo() {
        let a = Kuramoto(columns: 6, rows: 6, coupling: 3, spread: 0, range: 1, seed: 4)
        let b = Kuramoto(columns: 6, rows: 6, coupling: 3, spread: 0, range: 1, seed: 4)
        b.range = 2
        for _ in 0 ..< 60 {
            a.advance()
            b.advance()
        }
        #expect(a.phases != b.phases)
        b.range = 1
        let c = Kuramoto(columns: 6, rows: 6, coupling: 3, spread: 0, range: 1, seed: 4)
        c.phases = b.phases
        b.advance()
        c.advance()
        #expect(b.phases == c.phases)
    }

    // MARK: - Layers

    @Test func theLayersOfASiteRegisterUnderTheirOwnCoupling() {
        // Three oscillators a site, coupled to nothing but each other: every site's
        // three phases come together, while sites stay strangers.
        let sync = Kuramoto(columns: 5, rows: 4, layers: 3, coupling: 0, spread: 0.05,
                            range: 1, layerCoupling: 3, seed: 6)
        #expect(sync.count == 60)
        #expect(sync.sites == 20)
        for _ in 0 ..< 10 * 60 { sync.advance() }
        for s in 0 ..< 20 {
            let a = sync.phases[s * 3], b = sync.phases[s * 3 + 1], c = sync.phases[s * 3 + 2]
            #expect(abs(cos(a - b)) > 0.99)
            #expect(abs(cos(a - c)) > 0.99)
        }
        #expect(sync.coherence < 0.9)
    }

    @Test func eachLayerCouplesOverItsOwnCopyOfTheLattice() {
        // With the layer coupling off, layer 0 of a two-layer crowd steps exactly as
        // a one-layer crowd dealt the same phases and frequencies would.
        let two = Kuramoto(columns: 6, rows: 5, layers: 2, coupling: 2, spread: 0.3, range: 1, seed: 9)
        let one = Kuramoto(columns: 6, rows: 5, coupling: 2, spread: 0.3, range: 1, seed: 9)
        one.phases = (0 ..< 30).map { two.phases[$0 * 2] }
        one.frequencies = (0 ..< 30).map { two.frequencies[$0 * 2] }
        for _ in 0 ..< 120 {
            two.advance()
            one.advance()
        }
        #expect((0 ..< 30).allSatisfy { two.phases[$0 * 2] == one.phases[$0] })
        // The mean field is per layer too: layer 1's local order is its own r.
        let field = Kuramoto(columns: 6, rows: 5, layers: 2, coupling: 2, range: 0, seed: 9)
        var x = 0.0, y = 0.0
        for s in 0 ..< 30 { x += cos(field.phases[s * 2 + 1]); y += sin(field.phases[s * 2 + 1]) }
        let r = (x * x + y * y).squareRoot() / 30
        #expect(abs(field.localCoherence[1] - r) < 1e-12)
    }

    @Test func theLatticeSpellsItsAddresses() {
        let lattice = Kuramoto.Lattice(columns: 7, rows: 3)
        #expect(lattice.count == 21)
        #expect(lattice.index(column: 3, row: 2) == 17)
        #expect(lattice.column(of: 17) == 3)
        #expect(lattice.row(of: 17) == 2)
        let sync = Kuramoto(columns: 7, rows: 3, seed: 0)
        #expect(sync.lattice == lattice)
        #expect(Kuramoto(count: 4).lattice == nil)
    }

    // MARK: - The rates

    @Test func theRatesAreTheNaturalPaceUntilTheCrowdAdvances() {
        let sync = Kuramoto(count: 12, coupling: 2, seed: 3)
        #expect(sync.rates == sync.frequencies)
        sync.frequencies = sync.frequencies.map { $0 * 2 }
        #expect(sync.rates == sync.frequencies)   // it follows a spectrum handed over before the first frame
        sync.coupling = 0
        sync.advance()
        #expect(sync.rates == sync.frequencies)   // with no pull the rate is the natural pace
    }

    @Test func theRatesAreWhatTheLastSubstepMovedThePhasesBy() {
        // One substep (dt of 1/240 s) moves every phase by exactly rate * dt, so
        // the phases differenced across it, unwrapped, are the rates; on a
        // three-layer lattice with a lag and a layer coupling, since every term
        // of the pull is in the number.
        let sync = Kuramoto(columns: 6, rows: 5, layout: .hex, layers: 3, coupling: 3, spread: 0.4,
                            lag: 0.3, range: 1, layerCoupling: 1.5, seed: 12)
        for _ in 0 ..< 30 { sync.advance() }
        let before = sync.phases
        let h = 1.0 / 240
        sync.advance(by: h)
        #expect(sync.rates.count == 90)
        for i in 0 ..< 90 {
            var moved = sync.phases[i] - before[i]
            while moved < -.pi { moved += 2 * .pi }
            while moved > .pi { moved -= 2 * .pi }
            #expect(abs(moved / h - sync.rates[i]) < 1e-6)
            #expect(sync.rates[i] != sync.frequencies[i])   // the pull is in it
        }
    }
}
