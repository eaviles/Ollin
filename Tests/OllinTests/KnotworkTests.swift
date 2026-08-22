@testable import Ollin
import Testing

/// Pure-CPU checks on the weave. Two of these are what make a knot a knot
/// rather than a heap of lines, and neither can be seen reliably in a picture:
/// at every crossing exactly one of the two passes goes over, and following any
/// one cord the choice alternates the whole way around. A knot drawn that way is
/// alternating, which is what the eye reads as woven.
@Suite
struct KnotworkTests {

    private func design(columns: Int, rows: Int,
                        mirrors: [Kolam.Mirror] = []) -> Knotwork {
        Knotwork(grid: Grid(in: Rectangle(x: 0, y: 0, width: 200, height: 200),
                            columns: columns, rows: rows),
                 mirrors: mirrors)
    }

    /// Every pass of every cord, as the walk sees them.
    private func passes(_ knot: Knotwork) -> [(index: Int, point: SIMD2<Int>, isOver: Bool)] {
        let curve = MirrorCurve(columns: knot.grid.columns, rows: knot.grid.rows,
                                mirrors: knot.mirrors)
        return curve.loops.flatMap { Knotwork.passes(along: $0, of: curve) }
    }

    @Test func everyCrossingHasOneOverAndOneUnder() {
        for (columns, rows) in [(4, 4), (7, 5), (6, 4), (3, 8)] {
            let knot = design(columns: columns, rows: rows)
            var overs: [SIMD2<Int>: Int] = [:], unders: [SIMD2<Int>: Int] = [:]
            for pass in passes(knot) {
                if pass.isOver { overs[pass.point, default: 0] += 1 }
                else { unders[pass.point, default: 0] += 1 }
            }
            #expect(overs.count == unders.count, "\(columns) by \(rows)")
            // Sorted, so a failure names the same point every run.
            for point in overs.keys.sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }) {
                #expect(overs[point] == 1 && unders[point] == 1,
                        "at \(point): \(overs[point] ?? 0) over, \(unders[point] ?? 0) under")
            }
        }
    }

    @Test func everyCordAlternatesOverAndUnder() {
        let knot = design(columns: 7, rows: 5)
        let curve = MirrorCurve(columns: 7, rows: 5, mirrors: [])
        for (number, walk) in curve.loops.enumerated() {
            let along = Knotwork.passes(along: walk, of: curve).map(\.isOver)
            #expect(along.count % 2 == 0,
                    "cord \(number) crosses an odd number of times, so it cannot alternate")
            for step in 0 ..< along.count {
                #expect(along[step] != along[(step + 1) % along.count],
                        "cord \(number) repeats itself at crossing \(step)")
            }
        }
    }

    @Test func aPlainFieldHasTheCrossingsItsSizeAllows() {
        // Every point of the field is a crossing except the ones on the outside
        // edge, where the line turns and only one pass ever arrives.
        for (columns, rows) in [(1, 1), (4, 4), (7, 5), (8, 3)] {
            let knot = design(columns: columns, rows: rows)
            #expect(knot.crossings.count == 2 * columns * rows - columns - rows,
                    "\(columns) by \(rows) counted \(knot.crossings.count)")
        }
    }

    @Test func aWallTakesOneCrossingAway() {
        // A wall turns the line where two passes would otherwise have met.
        let plain = design(columns: 6, rows: 6).crossings.count
        let walled = design(columns: 6, rows: 6,
                            mirrors: [.rightOf(column: 2, row: 2), .below(column: 3, row: 2)])
        #expect(walled.crossings.count == plain - 2)
        // One asked for on the outside edge is dropped, so it takes nothing.
        let edge = design(columns: 6, rows: 6, mirrors: [.rightOf(column: 5, row: 2)])
        #expect(edge.crossings.count == plain)
    }

    @Test func eachCordIsBrokenOnceForEveryDive() {
        let knot = design(columns: 7, rows: 5)
        let curve = MirrorCurve(columns: 7, rows: 5, mirrors: [])
        let dives = curve.loops.map { walk in
            Knotwork.passes(along: walk, of: curve).filter { !$0.isOver }.count
        }
        let pieces = knot.bands()
        #expect(pieces.count == dives.reduce(0, +),
                "expected one piece per dive, got \(pieces.count) for \(dives.reduce(0, +))")
        #expect(pieces.allSatisfy { !$0.isClosed }, "a broken cord is open")
        #expect(pieces.allSatisfy { $0.points.count >= 2 })
        #expect(knot.cords.allSatisfy { $0.isClosed }, "the whole cords are not")
    }

    @Test func theGapIsTakenOutOfTheCordAndNothingElse() {
        // The pieces must be shorter than the whole cords by about one gap per
        // dive, which is the only thing the breaking is allowed to change.
        let knot = design(columns: 6, rows: 4)
        func length(_ contours: [Contour]) -> Double {
            contours.reduce(0) { total, contour in
                let points = contour.points
                guard points.count > 1 else { return total }
                var run = 0.0
                for i in 1 ..< points.count { run += (points[i] - points[i - 1]).length }
                if contour.isClosed, let first = points.first, let last = points.last {
                    run += (first - last).length
                }
                return total + run
            }
        }
        let gap = 6.0
        let dives = knot.bands(gap: gap).count
        let lost = length(knot.cords) - length(knot.bands(gap: gap))
        #expect(abs(lost - Double(dives) * gap) < 1e-9,
                "expected \(Double(dives) * gap) of cord taken out, measured \(lost)")
    }

    @Test func aFieldTooSmallToCrossComesBackWhole() {
        // One dot: the line goes around it and never meets itself, so there is
        // nothing to break and the cord stays closed.
        let knot = design(columns: 1, rows: 1)
        #expect(knot.crossings.isEmpty)
        #expect(knot.bands().count == 1)
        #expect(knot.bands().allSatisfy { $0.isClosed })
    }
}
