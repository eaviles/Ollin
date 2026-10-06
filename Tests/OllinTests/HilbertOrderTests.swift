import Testing
import Foundation
import Ollin

/// Points in the order of a Hilbert curve, pinned by the curve's own
/// properties rather than by a copy of its output: every cell of a grid is
/// visited once and each visit is a neighbor of the last, the four-by-four
/// curve is the classic one, the order is a permutation that repeats, a tour
/// in that order is far shorter than the given order, and points sharing a
/// cell keep their order. No GPU.
@Suite struct HilbertOrderTests {

    private func scatter(_ count: Int, seed: UInt64, side: Double = 1000) -> [Vector2] {
        var rng = SplitMix64(seed: seed)
        return (0 ..< count).map { _ in
            Vector2(Double.random(in: 0 ..< side, using: &rng), Double.random(in: 0 ..< side, using: &rng))
        }
    }

    private func pathLength(_ points: [Vector2]) -> Double {
        guard points.count > 1 else { return 0 }
        var total = 0.0
        for i in 1 ..< points.count { total += points[i - 1].distance(to: points[i]) }
        return total
    }

    // MARK: The curve itself

    @Test func everyCellIsVisitedOnceAndEachVisitIsANeighborOfTheLast() throws {
        for level in [1, 2, 3, 5, 7] {
            let n = 1 << level
            let unit = Rectangle(x: 0, y: 0, width: Double(n), height: Double(n))
            var visits: [(index: Int, x: Int, y: Int)] = []
            for y in 0 ..< n {
                for x in 0 ..< n {
                    let center = Vector2(Double(x) + 0.5, Double(y) + 0.5)
                    visits.append((hilbertIndex(of: center, in: unit, level: level), x, y))
                }
            }
            visits.sort { $0.index < $1.index }
            try #require(visits.count == n * n)
            for (place, visit) in visits.enumerated() {
                #expect(visit.index == place, "level \(level): index \(visit.index) at place \(place)")
            }
            for i in 1 ..< visits.count {
                let step = abs(visits[i].x - visits[i - 1].x) + abs(visits[i].y - visits[i - 1].y)
                #expect(step == 1, "level \(level): a jump of \(step) at visit \(i)")
            }
            #expect(visits[0].x == 0 && visits[0].y == 0)
            #expect(visits[visits.count - 1].x == n - 1 && visits[visits.count - 1].y == 0)
        }
    }

    @Test func theFourByFourCurveIsTheClassicOne() {
        let unit = Rectangle(x: 0, y: 0, width: 4, height: 4)
        let classic = [(0, 0), (1, 0), (1, 1), (0, 1), (0, 2), (0, 3), (1, 3), (1, 2),
                       (2, 2), (2, 3), (3, 3), (3, 2), (3, 1), (2, 1), (2, 0), (3, 0)]
        for (place, cell) in classic.enumerated() {
            let center = Vector2(Double(cell.0) + 0.5, Double(cell.1) + 0.5)
            #expect(hilbertIndex(of: center, in: unit, level: 2) == place)
        }
    }

    @Test func aPointOutsideTheBoundsReadsAtTheNearestCell() {
        let bounds = Rectangle(x: 100, y: 100, width: 200, height: 200)
        #expect(hilbertIndex(of: Vector2(-50, -50), in: bounds, level: 4) == hilbertIndex(of: Vector2(100, 100), in: bounds, level: 4))
        #expect(hilbertIndex(of: Vector2(900, 100), in: bounds, level: 4) == hilbertIndex(of: Vector2(299.9, 100), in: bounds, level: 4))
        #expect(hilbertIndex(of: Vector2(100, 100), in: bounds, level: 4) == 0)
        #expect(hilbertIndex(of: Vector2(299.9, 100), in: bounds, level: 4) == 255)
        // A level past the range is held to it, and a bounds with no height
        // reads every point on its first row.
        #expect(hilbertIndex(of: Vector2(150, 150), in: bounds, level: 0) == hilbertIndex(of: Vector2(150, 150), in: bounds, level: 1))
        #expect(hilbertIndex(of: Vector2(150, 150), in: bounds, level: 99) == hilbertIndex(of: Vector2(150, 150), in: bounds, level: 30))
        let flat = Rectangle(x: 0, y: 0, width: 100, height: 0)
        #expect(hilbertIndex(of: Vector2(10, 500), in: flat, level: 3) == hilbertIndex(of: Vector2(10, 0), in: flat, level: 3))
    }

    // MARK: The sort

    @Test func theOrderIsAPermutationAndRepeats() {
        let points = scatter(2000, seed: 5)
        let order = hilbertOrder(of: points)
        #expect(order.count == points.count)
        #expect(Set(order).count == points.count)
        #expect(hilbertSorted(points) == order.map { points[$0] })
        #expect(hilbertOrder(of: points) == order)
        #expect(hilbertOrder(of: points.map { $0 * 3 + Vector2(500, -200) }) == order)
    }

    @Test func theTourIsFarShorterThanTheGivenOrder() {
        let points = scatter(3000, seed: 8)
        let given = pathLength(points)
        let sorted = pathLength(hilbertSorted(points))
        #expect(sorted < given / 15)
        // A tour that keeps neighbors together grows with the square root of
        // the count, not the count: for n points evenly spread over a square
        // of side s, under one and a half times s times root n.
        #expect(sorted < 1.5 * 1000 * Double(points.count).squareRoot())
    }

    @Test func pointsInOneCellKeepTheirGivenOrder() {
        // Level 1 is four cells, visited top left, bottom left, bottom right,
        // top right as the canvas shows them. Three points per cell, given in
        // a scrambled order.
        let cells = [Vector2(100, 100), Vector2(100, 700), Vector2(700, 700), Vector2(700, 100)]
        var points: [Vector2] = []
        var home: [Int] = []
        for k in 0 ..< 3 {
            for (c, cell) in cells.enumerated().reversed() {
                points.append(cell + Vector2(Double(k) * 20, Double(k) * 10))
                home.append(c)
            }
        }
        // The far corners pin the bounds to the whole square.
        points.append(Vector2(0, 0))
        points.append(Vector2(800, 800))
        home.append(0)
        home.append(2)
        let order = hilbertOrder(of: points, level: 1)
        let visited = order.map { home[$0] }
        #expect(visited == [0, 0, 0, 0, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3])
        for cell in 0 ..< 4 {
            let mine = order.filter { home[$0] == cell }
            #expect(mine == mine.sorted())
        }
    }

    @Test func degenerateInputsAreSafe() {
        #expect(hilbertOrder(of: []).isEmpty)
        #expect(hilbertSorted([]).isEmpty)
        #expect(hilbertOrder(of: [Vector2(3, 4)]) == [0])
        let same = [Vector2](repeating: Vector2(5, 5), count: 12)
        #expect(hilbertOrder(of: same) == Array(0 ..< 12))
        let row = (0 ..< 50).map { Vector2(Double($0) * 7, 40) }
        #expect(Set(hilbertOrder(of: row)).count == 50)
        let column = (0 ..< 50).map { Vector2(40, Double($0) * 7) }
        #expect(Set(hilbertOrder(of: column)).count == 50)
        let withBad = [Vector2(0, 0), Vector2(.nan, 1), Vector2(10, 10), Vector2(.infinity, 3)]
        #expect(Set(hilbertOrder(of: withBad)).count == 4)
    }
}
