import Ollin
import Testing

/// Pure-CPU checks on `CrackGrowth`: the run repeats from its seed, cracks
/// multiply on collision up to the cap, stopped runs archive as segments, and
/// the wash grains stay on the span with fading alpha. No GPU.
@Suite
struct CrackGrowthTests {
    @Test
    func theSameSeedRepeatsTheSameRun() {
        let a = CrackGrowth(width: 300, height: 300, seed: 9)
        let b = CrackGrowth(width: 300, height: 300, seed: 9)
        let marksA = a.step(400)
        let marksB = b.step(400)
        #expect(marksA.count == marksB.count)
        for (m, n) in zip(marksA, marksB) {
            #expect(m.crack == n.crack)
            #expect(m.point == n.point)
            #expect(m.washExtent == n.washExtent)
            #expect(m.gain == n.gain)
        }
    }

    @Test
    func aDifferentSeedRunsDifferently() {
        let a = CrackGrowth(width: 300, height: 300, seed: 1)
        let b = CrackGrowth(width: 300, height: 300, seed: 2)
        let pointsA = a.step(60).map(\.point)
        let pointsB = b.step(60).map(\.point)
        #expect(pointsA != pointsB)
    }

    @Test
    func cracksMultiplyUpToTheCap() {
        let field = CrackGrowth(width: 200, height: 200, cracks: 3,
                                maxCracks: 40, seed: 5)
        #expect(field.count == 3)
        field.step(4000)
        #expect(field.count > 3)
        #expect(field.count <= 40)
    }

    @Test
    func stoppedRunsArchiveAsSegments() {
        let field = CrackGrowth(width: 200, height: 200, seed: 3)
        field.step(2000)
        let segments = field.segments
        #expect(!segments.isEmpty)
        // Every archived line has real length, and both ends sit on or near
        // the canvas (a colliding tick can overshoot by at most one step).
        for (a, b) in segments {
            #expect(a.distance(to: b) > 0)
            for p in [a, b] {
                #expect(p.x > -2 && p.x < 202)
                #expect(p.y > -2 && p.y < 202)
            }
        }
    }

    @Test
    func marksArriveOnePerLivingCrackEachTick() {
        let field = CrackGrowth(width: 300, height: 300, cracks: 3, seed: 11)
        let first = field.step()
        #expect(first.count == 3)
        for mark in first {
            #expect(mark.crack >= 0 && mark.crack < field.count)
            #expect(mark.gain >= 0 && mark.gain <= 1)
        }
    }

    @Test
    func theWashStaysOnOneSideOfTheLine() {
        let field = CrackGrowth(width: 300, height: 300, seed: 7)
        let first = field.step()
        let second = field.step()
        // Two ticks of the same crack give its travel direction; the wash
        // span must sit perpendicular to it, always on the same side (the
        // cross product's sign is fixed by construction).
        var checked = 0
        for (a, b) in zip(first, second) where a.crack == b.crack {
            let dir = b.point - a.point
            let span = b.washExtent - b.point
            // A restart between the ticks jumps far; a travel step is short.
            guard dir.length > 0.01, dir.length < 1, span.length > 0.01 else { continue }
            let cross = dir.x * span.y - dir.y * span.x
            let dot = dir.x * span.x + dir.y * span.y
            #expect(cross < 0)
            #expect(abs(dot) < 1e-6 * dir.length * span.length + 1e-9)
            checked += 1
        }
        #expect(checked > 0)
    }

    @Test
    func grainsWalkTheSpanAndFade() {
        let from = Vector2(10, 10)
        let to = Vector2(110, 10)
        let grains = CrackGrowth.grains(from: from, to: to, gain: 1, count: 64)
        #expect(grains.count == 64)
        // Positions run outward from the crack, never past the span.
        var last = -1.0
        for grain in grains {
            let f = (grain.position.x - from.x) / (to.x - from.x)
            #expect(f >= last - 1e-9)
            #expect(f >= 0 && f <= 1)
            last = f
        }
        // At full gain the wash reaches most of the span but fades before
        // the far edge.
        let reach = (grains.last!.position.x - from.x) / (to.x - from.x)
        #expect(reach > 0.5 && reach < 0.9)
        // Alpha fades from the crack outward.
        #expect(grains.first!.alpha > grains.last!.alpha)
        #expect(abs(grains.first!.alpha - 0.1) < 1e-9)
    }

    @Test
    func aZeroGainWashPilesAtTheCrack() {
        let grains = CrackGrowth.grains(from: .zero, to: Vector2(100, 0), gain: 0)
        for grain in grains {
            #expect(grain.position.distance(to: .zero) < 1e-9)
        }
    }
}
