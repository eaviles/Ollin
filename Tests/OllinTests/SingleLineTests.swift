import Ollin
import Testing

/// Pure-CPU checks on `singleLine(through:)`: the tour visits every point
/// exactly once, 2-opt only ever shortens the nearest-neighbor order, the
/// open form cuts the longest edge, and the tour is deterministic. No GPU.
@Suite
struct SingleLineTests {
    /// A seeded scatter of points to tour.
    private func scatter(_ count: Int, seed: UInt64) -> [Vector2] {
        var rng = SplitMix64(seed: seed)
        return (0 ..< count).map { _ in
            Vector2(Double.random(in: 0 ..< 400, using: &rng),
                    Double.random(in: 0 ..< 300, using: &rng))
        }
    }

    private func tourLength(_ contour: Contour) -> Double {
        var total = 0.0
        let pts = contour.points
        guard pts.count > 1 else { return 0 }
        for i in 1 ..< pts.count { total += pts[i - 1].distance(to: pts[i]) }
        if contour.isClosed { total += pts.last!.distance(to: pts[0]) }
        return total
    }

    /// The tour is a permutation: every input point appears exactly once.
    @Test func tourVisitsEveryPointOnce() {
        let points = scatter(300, seed: 5)
        let tour = singleLine(through: points)
        #expect(tour.points.count == points.count)
        #expect(tour.isClosed)
        let inputSet = Set(points.map { "\($0.x),\($0.y)" })
        let tourSet = Set(tour.points.map { "\($0.x),\($0.y)" })
        #expect(inputSet == tourSet)
    }

    /// The improved tour is never longer than walking the points in their
    /// given order, and in practice is far shorter.
    @Test func tourBeatsTheGivenOrder() {
        let points = scatter(400, seed: 8)
        let tour = singleLine(through: points)
        let given = tourLength(Contour(points, closed: true))
        #expect(tourLength(tour) < given)
    }

    /// The same points tour the same way.
    @Test func tourIsDeterministic() {
        let points = scatter(250, seed: 13)
        let a = singleLine(through: points)
        let b = singleLine(through: points)
        #expect(a.points == b.points)
    }

    /// The open form has the same points, is not closed, and its walked
    /// length is the closed tour minus that tour's longest edge.
    @Test func openFormCutsTheLongestEdge() {
        let points = scatter(120, seed: 21)
        let closed = singleLine(through: points, closed: true)
        let open = singleLine(through: points, closed: false)
        #expect(!open.isClosed)
        #expect(open.points.count == points.count)

        var longest = 0.0
        let pts = closed.points
        for i in 0 ..< pts.count {
            longest = max(longest, pts[i].distance(to: pts[(i + 1) % pts.count]))
        }
        #expect(abs(tourLength(open) - (tourLength(closed) - longest)) < 1e-6)
    }

    /// Degenerate inputs pass through without trouble.
    @Test func degenerateInputsAreSafe() {
        #expect(singleLine(through: []).points.isEmpty)
        #expect(singleLine(through: [Vector2(1, 1)]).points.count == 1)
        #expect(singleLine(through: [Vector2(1, 1), Vector2(2, 2)]).points.count == 2)
        // Coincident points: still a permutation, no hang.
        let same = [Vector2](repeating: Vector2(5, 5), count: 20)
        #expect(singleLine(through: same).points.count == 20)
        // Collinear points: the tour walks the line.
        let line = (0 ..< 50).map { Vector2(Double($0) * 3, 10) }
        #expect(singleLine(through: line).points.count == 50)
    }
}
