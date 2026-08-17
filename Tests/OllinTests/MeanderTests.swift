import Foundation
import Ollin
import Testing

/// Pure-CPU checks on `Meander`: the run repeats from its seed, bends grow
/// from the wavy seed and a cutoff eventually arrives on its own, a pinched
/// loop cuts off into an oxbow that shrinks and dies, the resample keeps an
/// even spacing, and the pinned ends hold. No GPU.
@Suite
struct MeanderTests {
    /// An omega-shaped channel whose neck is already inside the cutoff
    /// distance: most of a circle, so one step must cut the loop off.
    private func pinchedLoop(oxbowShrink: Double = 0.008) -> Meander {
        let radius = 80.0
        let count = 80
        let points = (0 ... count).map { i -> Vector2 in
            // Sweep 340 degrees, leaving a 27.8-unit neck (under the default
            // cutoff distance of two widths).
            let angle = (170.0 - 340.0 * Double(i) / Double(count)) * .pi / 180
            return Vector2(radius * cos(angle), radius * sin(angle))
        }
        return Meander(centerline: points, seed: 5, width: 24,
                       oxbowShrink: oxbowShrink)
    }

    @Test
    func theSameSeedRepeatsTheSameRun() {
        let a = Meander.line(from: Vector2(0, 300), to: Vector2(900, 300),
                             seed: 9, width: 24, recordEvery: 25)
        let b = Meander.line(from: Vector2(0, 300), to: Vector2(900, 300),
                             seed: 9, width: 24, recordEvery: 25)
        a.step(300)
        b.step(300)
        #expect(a.centerline == b.centerline)
        #expect(a.oxbows.count == b.oxbows.count)
        for (m, n) in zip(a.oxbows, b.oxbows) {
            #expect(m.points == n.points)
            #expect(m.age == n.age)
        }
        #expect(a.scars.count == b.scars.count)
    }

    @Test
    func aDifferentSeedRunsDifferently() {
        let a = Meander.line(from: Vector2(0, 300), to: Vector2(900, 300),
                             seed: 1, width: 24)
        let b = Meander.line(from: Vector2(0, 300), to: Vector2(900, 300),
                             seed: 2, width: 24)
        a.step(60)
        b.step(60)
        #expect(a.centerline != b.centerline)
    }

    @Test
    func bendsGrowFromTheWavySeed() {
        let river = Meander.line(from: Vector2(0, 300), to: Vector2(900, 300),
                                 seed: 7, width: 24)
        let atStart = river.sinuosity
        #expect(atStart < 1.2)          // the seed is only gently wavy
        river.step(800)
        #expect(river.sinuosity > 1.4)  // measured 1.84; leave slack for tuning
    }

    @Test
    func aCutoffArrivesOnItsOwn() {
        let river = Meander.line(from: Vector2(0, 300), to: Vector2(900, 300),
                                 seed: 7, width: 24)
        var sawOxbow = false
        for _ in 0 ..< 1600 {
            river.step()
            if !river.oxbows.isEmpty { sawOxbow = true; break }
        }
        #expect(sawOxbow)               // measured: first cutoff before step 1600
    }

    @Test
    func theResampleKeepsAnEvenSpacing() {
        let river = Meander.line(from: Vector2(0, 300), to: Vector2(900, 300),
                                 seed: 3, width: 24)
        river.step(400)
        for i in 1 ..< river.centerline.count {
            let d = river.centerline[i].distance(to: river.centerline[i - 1])
            #expect(d > river.spacing * 0.5 && d < river.spacing * 1.5)
        }
    }

    @Test
    func thePinnedEndsStayPut() {
        let start = Vector2(0, 300)
        let end = Vector2(900, 300)
        let river = Meander.line(from: start, to: end, seed: 11, width: 24)
        river.step(200)
        #expect(river.centerline.first!.distance(to: start) < 1e-6)
        #expect(river.centerline.last!.distance(to: end) < 1e-6)
    }

    @Test
    func aPinchedLoopCutsOffIntoAnOxbow() {
        let loop = pinchedLoop()
        let before = loop.count
        loop.step()
        #expect(loop.oxbows.count == 1)
        #expect(loop.count < before / 2)               // the loop is gone
        #expect(loop.oxbows.first!.points.count > 20)  // and kept as the lake
        #expect(loop.oxbows.first!.age == 1)
    }

    @Test
    func oxbowsShrinkAndDie() {
        let loop = pinchedLoop(oxbowShrink: 0.05)
        loop.step()
        let young = extent(of: loop.oxbows.first!)
        loop.step(5)
        if let older = loop.oxbows.first {
            #expect(extent(of: older) < young)
            loop.step(100)
        }
        #expect(loop.oxbows.isEmpty)    // shrunk under the width and deleted
    }

    @Test
    func scarsRecordAtTheCadence() {
        let river = Meander.line(from: Vector2(0, 300), to: Vector2(900, 300),
                                 seed: 4, width: 24, recordEvery: 25)
        river.step(300)
        #expect(river.scars.count == 12)
        river.maxScars = 5
        river.step(50)
        #expect(river.scars.count == 5)  // the oldest dropped past the ceiling
    }

    /// The widest span of an oxbow's points, a scale-free size to watch shrink.
    private func extent(of oxbow: Meander.Oxbow) -> Double {
        var lowX = Double.infinity, highX = -Double.infinity
        var lowY = Double.infinity, highY = -Double.infinity
        for p in oxbow.points {
            lowX = Swift.min(lowX, p.x); highX = Swift.max(highX, p.x)
            lowY = Swift.min(lowY, p.y); highY = Swift.max(highY, p.y)
        }
        return Swift.max(highX - lowX, highY - lowY)
    }
}
