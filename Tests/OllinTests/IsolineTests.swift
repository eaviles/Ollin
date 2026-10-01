import Ollin
import Testing

/// Pure-CPU checks on `isolines(at:in:resolution:field:)`: a circular field
/// traces one closed ring of the right size, a ramp traces straight open
/// lines ending on the bounds, the multi-level form matches per-level calls,
/// and the trace is deterministic. No GPU.
@Suite
struct IsolineTests {
    private let bounds = Rectangle(x: 0, y: 0, width: 400, height: 300)

    /// A radial field crossed at one level yields a single closed ring whose
    /// points sit on the circle, at the sampled circumference.
    @Test func circularFieldTracesOneClosedRing() {
        let center = Vector2(200, 150)
        let rings = isolines(at: 100, in: bounds, resolution: 200) { p in
            p.distance(to: center)
        }
        #expect(rings.count == 1)
        guard let ring = rings.first else { return }
        #expect(ring.isClosed)
        #expect(ring.points.count > 40)
        for p in ring.points {
            #expect(abs(p.distance(to: center) - 100) < 2.5)
        }
        var length = 0.0
        for i in 1 ..< ring.points.count {
            length += ring.points[i - 1].distance(to: ring.points[i])
        }
        length += ring.points.last!.distance(to: ring.points[0])
        #expect(abs(length - 2 * .pi * 100) < 0.02 * 2 * .pi * 100)
    }

    /// A linear ramp's contour is one open chain pinned to the level's
    /// coordinate, with both ends on the bounds edge.
    @Test func rampTracesOneOpenLineToTheBounds() {
        let lines = isolines(at: 137, in: bounds, resolution: 100) { p in p.x }
        #expect(lines.count == 1)
        guard let line = lines.first else { return }
        #expect(!line.isClosed)
        for p in line.points {
            #expect(abs(p.x - 137) < 1e-9)
        }
        let ys = [line.points.first!.y, line.points.last!.y].sorted()
        #expect(abs(ys[0] - 0) < 1e-9)
        #expect(abs(ys[1] - 300) < 1e-9)
    }

    /// The multi-level form matches level-by-level calls from one sampling.
    @Test func levelsFormMatchesSingleLevelCalls() {
        func field(_ p: Vector2) -> Double {
            p.distance(to: Vector2(180, 140)) + 24 * (0.5 - 0.5 * cos(p.x * 0.03))
        }
        let stacked = isolines(at: [60, 90, 120], in: bounds, resolution: 150, field: field)
        #expect(stacked.count == 3)
        for (level, group) in zip([60.0, 90, 120], stacked) {
            let single = isolines(at: level, in: bounds, resolution: 150, field: field)
            #expect(group.count == single.count)
            #expect(zip(group, single).allSatisfy {
                $0.points == $1.points && $0.isClosed == $1.isClosed
            })
        }
    }

    /// The stack form marches once and visits each cell only for the levels
    /// between its lowest and highest corner, so it has to agree with a march
    /// per level exactly, on the edges of that range too: levels out of order
    /// and repeated, levels outside the field, levels landing exactly on
    /// corner values (a staircase field, where most corners sit on a level),
    /// corners that are NaN, and a NaN level.
    @Test func oneMarchAgreesWithAMarchPerLevel() {
        func expectSame(_ levels: [Double], resolution: Int, _ field: (Vector2) -> Double,
                        _ name: String) {
            let stacked = isolines(at: levels, in: bounds, resolution: resolution, field: field)
            #expect(stacked.count == levels.count, "\(name)")
            for (level, group) in zip(levels, stacked) {
                let single = isolines(at: level, in: bounds, resolution: resolution, field: field)
                let same = group.count == single.count && zip(group, single).allSatisfy {
                    $0.points == $1.points && $0.isClosed == $1.isClosed
                }
                #expect(same, "\(name): level \(level) gives \(group.count) contours, alone \(single.count)")
            }
        }
        func ripples(_ p: Vector2) -> Double {
            sin(p.x * 0.041) * 40 + cos(p.y * 0.053 + p.x * 0.011) * 35 + sin((p.x + p.y) * 0.019) * 25
        }
        let levels = (0 ..< 28).map { -95 + Double(($0 * 11) % 28) * 7 }   // a shuffled ladder
        expectSame(levels + [levels[3], levels[3], -500, 500], resolution: 160, ripples, "ripples")

        func staircase(_ p: Vector2) -> Double { Double(Int(p.x / 23) + Int(p.y / 31)) }
        expectSame((0 ... 30).map(Double.init).reversed(), resolution: 90, staircase, "staircase")

        func holed(_ p: Vector2) -> Double {
            p.distance(to: Vector2(200, 150)) < 60 ? .nan : ripples(p)
        }
        expectSame([-40, -10, 0, 10, 40, .nan], resolution: 120, holed, "NaN corners")
        #expect(isolines(at: [.nan], in: bounds, field: ripples) == [[]], "a NaN level crosses nothing")
    }

    /// A field that is NaN or infinite somewhere has no contour there: a ring
    /// crossing the hole comes back as one open line with every point finite,
    /// where a crossing interpolated against the hole used to land on NaN and
    /// stop the program.
    @Test func aHoleInTheFieldOpensTheRing() {
        func field(_ p: Vector2) -> Double {
            if p.x > 260 { return p.y > 150 ? .nan : .infinity }
            return p.distance(to: Vector2(200, 150))
        }
        for contours in [isolines(at: 80, in: bounds, resolution: 160, field: field),
                         isolines(at: [80], in: bounds, resolution: 160, field: field)[0]] {
            #expect(contours.count == 1)
            #expect(contours.first?.isClosed == false)
            #expect(contours.allSatisfy { $0.points.allSatisfy { $0.x.isFinite && $0.y.isFinite } })
            #expect(contours.first.map { $0.points.allSatisfy { $0.x <= 261 } } == true)
        }
    }

    /// A hyperbolic saddle field separates into its two branches (the
    /// cell-average rule keeps them from crossing into an X).
    @Test func saddleFieldKeepsItsBranchesApart() {
        let centered = Rectangle(x: -1, y: -1, width: 2, height: 2)
        let branches = isolines(at: 0.05, in: centered, resolution: 64) { p in p.x * p.y }
        #expect(branches.count == 2)
        #expect(branches.allSatisfy { !$0.isClosed })
        // Each branch stays in one quadrant pair: x and y share a sign.
        for branch in branches {
            let signs = Set(branch.points.map { ($0.x >= 0) == ($0.y >= 0) })
            #expect(signs.count == 1)
        }
    }

    /// The same field traces the same way.
    @Test func traceIsDeterministic() {
        func field(_ p: Vector2) -> Double { sin(p.x * 0.05) + cos(p.y * 0.07) }
        let a = isolines(at: 0.3, in: bounds, resolution: 120, field: field)
        let b = isolines(at: 0.3, in: bounds, resolution: 120, field: field)
        #expect(a.count == b.count)
        #expect(zip(a, b).allSatisfy { $0.points == $1.points && $0.isClosed == $1.isClosed })
    }

    /// Fields that never cross the level, degenerate bounds, and a floored
    /// resolution all come back empty or safe.
    @Test func degenerateInputsAreSafe() {
        #expect(isolines(at: 0.5, in: bounds) { _ in 2 }.isEmpty)
        #expect(isolines(at: 0.5, in: bounds) { _ in 0.5 }.isEmpty)
        let flat = Rectangle(x: 0, y: 0, width: 0, height: 100)
        #expect(isolines(at: 0.5, in: flat) { p in p.y }.isEmpty)
        let tiny = isolines(at: 100, in: bounds, resolution: 0) { p in p.x }
        #expect(tiny.count <= 1)
    }
}
