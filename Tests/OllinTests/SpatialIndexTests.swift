import Foundation
import Ollin
import Testing

/// Pure-CPU checks on `SpatialIndex`. The law every test leans on is that an
/// index is only ever a faster way to ask a question that has one right answer:
/// whatever it says, a plain loop over every point has to say the same thing,
/// index for index and in the same order. Both kinds are held to it, over point
/// sets picked to be awkward (clumped, in a line, piled on one spot), from query
/// points inside the set and far outside it. No GPU.
@Suite
struct SpatialIndexTests {

    // MARK: - The brute-force answers the index has to match

    /// The nearest point, ties going to the lower index.
    static func bruteNearest(_ points: [Vector2], _ p: Vector2) -> Int? {
        var best = -1, bestD2 = Double.infinity
        for i in points.indices {
            let d2 = points[i].distanceSquared(to: p)
            if best < 0 || d2 < bestD2 || (d2 == bestD2 && i < best) { bestD2 = d2; best = i }
        }
        return best >= 0 ? best : nil
    }

    /// The `k` nearest, ascending by distance and then by index.
    static func bruteKNearest(_ points: [Vector2], _ k: Int, _ p: Vector2) -> [Int] {
        var ranked: [(d2: Double, i: Int)] = []
        for i in points.indices { ranked.append((points[i].distanceSquared(to: p), i)) }
        ranked.sort { $0.d2 != $1.d2 ? $0.d2 < $1.d2 : $0.i < $1.i }
        let want: Int = Swift.min(k, points.count)
        var answer: [Int] = []
        for entry in ranked.prefix(want) { answer.append(entry.i) }
        return answer
    }

    /// Everything within the radius, ascending by index.
    static func bruteNeighbors(_ points: [Vector2], _ p: Vector2,
                               _ radius: Double) -> [Int] {
        points.indices.filter { points[$0].distanceSquared(to: p) <= radius * radius }
    }

    /// Everything inside the region, ascending by index.
    static func bruteRegion(_ points: [Vector2], _ region: Rectangle) -> [Int] {
        points.indices.filter { region.contains(points[$0]) }
    }

    // MARK: - The awkward point sets

    /// Named point sets, each shaped to break a different assumption.
    static func sets() -> [(name: String, points: [Vector2])] {
        var uniform: [Vector2] = [], clumped: [Vector2] = []
        var line: [Vector2] = [], piled: [Vector2] = []
        var state: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Double {   // a plain deterministic generator, no framework
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        for _ in 0 ..< 400 { uniform.append(Vector2(next() * 600, next() * 600)) }
        for c in 0 ..< 6 {                       // six tight clumps, wide gaps
            let center = Vector2(60 + Double(c % 3) * 250, 60 + Double(c / 3) * 400)
            for _ in 0 ..< 50 {
                clumped.append(center + Vector2(next() * 8 - 4, next() * 8 - 4))
            }
        }
        for i in 0 ..< 200 { line.append(Vector2(Double(i) * 3, 250)) }   // no height
        for _ in 0 ..< 60 { piled.append(Vector2(100, 100)) }             // all one spot
        return [("uniform", uniform), ("clumped", clumped),
                ("line", line), ("piled", piled),
                ("one", [Vector2(30, 40)]), ("none", [])]
    }

    /// Query points: inside the set, on top of a point, and well outside the box
    /// in every direction, which is where a clamped cell lookup goes wrong.
    static func probes(_ points: [Vector2]) -> [Vector2] {
        var probes = [Vector2(300, 300), Vector2(0, 0), Vector2(-500, -500),
                      Vector2(1200, 300), Vector2(300, -800), Vector2(-40, 610)]
        if let first = points.first { probes.append(first) }
        if points.count > 7 { probes.append(points[7]) }
        return probes
    }

    // MARK: - The law

    @Test(arguments: [SpatialIndex.Kind.grid, .tree])
    func everyQueryAgreesWithAPlainLoop(kind: SpatialIndex.Kind) {
        for set in SpatialIndexTests.sets() {
            let index = SpatialIndex(set.points, kind: kind)
            #expect(index.count == set.points.count, "\(set.name)")
            for p in SpatialIndexTests.probes(set.points) {
                let where_ = "\(set.name)/\(kind)/\(p)"
                #expect(index.nearest(to: p) == SpatialIndexTests.bruteNearest(set.points, p),
                        "nearest \(where_)")
                for k in [1, 3, 7, 40] {
                    #expect(index.kNearest(k, to: p)
                            == SpatialIndexTests.bruteKNearest(set.points, k, p),
                            "kNearest \(k) \(where_)")
                }
                for r in [0.5, 5.0, 30.0, 200.0] {
                    #expect(index.neighbors(of: p, within: r)
                            == SpatialIndexTests.bruteNeighbors(set.points, p, r),
                            "neighbors \(r) \(where_)")
                    let all = SpatialIndexTests.bruteNeighbors(set.points, p, r)
                    if let any = index.anyNeighbor(of: p, within: r) {
                        #expect(all.contains(any), "anyNeighbor \(r) \(where_)")
                    } else {
                        #expect(all.isEmpty, "anyNeighbor \(r) \(where_)")
                    }
                    #expect(index.hasNeighbor(of: p, within: r) == !all.isEmpty,
                            "hasNeighbor \(r) \(where_)")
                }
            }
            for region in [Rectangle(x: 100, y: 100, width: 200, height: 150),
                           Rectangle(x: -50, y: -50, width: 40, height: 40),
                           Rectangle(x: 0, y: 0, width: 2000, height: 2000),
                           Rectangle(x: 100, y: 100, width: 0, height: 0)] {
                #expect(index.indices(in: region)
                        == SpatialIndexTests.bruteRegion(set.points, region),
                        "region \(set.name)/\(kind)")
            }
        }
    }

    /// The cell size is a speed knob, so a query has to answer the same whatever
    /// it is set to, including sizes far smaller and far larger than the spacing.
    @Test
    func theAnswerDoesNotDependOnTheCellSize() {
        let points = SpatialIndexTests.sets()[0].points
        let reference = SpatialIndex(points)
        for size in [0.5, 7.0, 61.0, 5000.0] {
            let index = SpatialIndex(points, cellSize: size)
            for p in SpatialIndexTests.probes(points).prefix(4) {
                #expect(index.nearest(to: p) == reference.nearest(to: p), "cell \(size)")
                #expect(index.kNearest(5, to: p) == reference.kNearest(5, to: p),
                        "cell \(size)")
                #expect(index.neighbors(of: p, within: 40)
                        == reference.neighbors(of: p, within: 40), "cell \(size)")
            }
        }
    }

    /// Points piled on one spot are all at the same distance, so the tie rule is
    /// the only thing deciding the answer.
    @Test(arguments: [SpatialIndex.Kind.grid, .tree])
    func equalDistancesAnswerWithTheLowerIndex(kind: SpatialIndex.Kind) {
        let points = (0 ..< 40).map { _ in Vector2(200, 200) } + [Vector2(500, 500)]
        let index = SpatialIndex(points, kind: kind)
        #expect(index.nearest(to: Vector2(210, 200)) == 0)
        #expect(index.kNearest(3, to: Vector2(210, 200)) == [0, 1, 2])
        // A point exactly between two others is the case a ring search can get
        // wrong by stopping as soon as it has found something.
        let pair = [Vector2(100, 100), Vector2(300, 100)]
        let between = SpatialIndex(pair, kind: kind)
        #expect(between.nearest(to: Vector2(200, 100)) == 0)
        #expect(between.kNearest(2, to: Vector2(200, 100)) == [0, 1])
    }

    // MARK: - Growing a set

    @Test(arguments: [SpatialIndex.Kind.grid, .tree])
    func aGrowingIndexAgreesWithAPlainLoop(kind: SpatialIndex.Kind) {
        var index = SpatialIndex(bounds: Rectangle(x: 0, y: 0, width: 200, height: 200),
                                 cellSize: 20, kind: kind)
        var points: [Vector2] = []
        var state: UInt64 = 12345
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        for step in 0 ..< 120 {
            // Half the points land outside the box it was built with, so the
            // grid has to grow rather than fold them into an edge cell.
            let spread = step < 60 ? 200.0 : 900.0
            let p = Vector2(next() * spread - spread / 4, next() * spread - spread / 4)
            let handed = index.insert(p)
            points.append(p)
            #expect(handed == points.count - 1)
            #expect(index.points == points)
            let probe = Vector2(next() * 400 - 100, next() * 400 - 100)
            #expect(index.nearest(to: probe)
                    == SpatialIndexTests.bruteNearest(points, probe), "step \(step)")
            #expect(index.neighbors(of: probe, within: 55)
                    == SpatialIndexTests.bruteNeighbors(points, probe, 55), "step \(step)")
        }
        #expect(index.count == 120)
    }

    /// The self-excluding form is what a flock or a relaxation calls: every point
    /// asks about the others, and must never find itself.
    @Test(arguments: [SpatialIndex.Kind.grid, .tree])
    func thePointItselfIsLeftOut(kind: SpatialIndex.Kind) {
        let points = SpatialIndexTests.sets()[1].points   // the clumped set
        let index = SpatialIndex(points, kind: kind)
        for i in stride(from: 0, to: points.count, by: 17) {
            let expected = SpatialIndexTests.bruteNeighbors(points, points[i], 12)
                .filter { $0 != i }
            #expect(index.neighbors(of: i, within: 12) == expected, "point \(i)")
        }
        // A point piled on top of another still leaves out only itself, never
        // the twin sitting at the same place.
        let twins = SpatialIndex([Vector2(50, 50), Vector2(50, 50)], kind: kind)
        #expect(twins.neighbors(of: 0, within: 1) == [1])
        #expect(twins.neighbors(of: 1, within: 1) == [0])
    }

    @Test(arguments: [SpatialIndex.Kind.grid, .tree])
    func anEmptyIndexAnswersNothing(kind: SpatialIndex.Kind) {
        let index = SpatialIndex([], kind: kind)
        #expect(index.isEmpty)
        #expect(index.nearest(to: .zero) == nil)
        #expect(index.kNearest(4, to: .zero).isEmpty)
        #expect(index.neighbors(of: Vector2.zero, within: 100).isEmpty)
        #expect(index.anyNeighbor(of: .zero, within: 100) == nil)
        #expect(index.indices(in: Rectangle(x: -1e6, y: -1e6,
                                            width: 2e6, height: 2e6)).isEmpty)
    }

    /// Nonsense arguments answer with nothing rather than trapping.
    @Test
    func awkwardArgumentsAreRefusedQuietly() {
        let index = SpatialIndex([Vector2(10, 10), Vector2(20, 20)])
        #expect(index.kNearest(0, to: .zero).isEmpty)
        #expect(index.kNearest(-3, to: .zero).isEmpty)
        #expect(index.kNearest(99, to: .zero).count == 2)
        #expect(index.neighbors(of: Vector2.zero, within: -5).isEmpty)
        #expect(index.neighbors(of: 7, within: 5).isEmpty)      // no such point
        // A coordinate this large squares into infinity, so every point is
        // equally far and the tie rule decides. The answer is still a point.
        #expect(index.nearest(to: Vector2(1e300, -1e300)) == 0)
    }

    /// The closure form allocates nothing, so it is the one a per-frame loop
    /// calls. Its walk has to repeat exactly, or a sketch stops reproducing.
    @Test(arguments: [SpatialIndex.Kind.grid, .tree])
    func theWalkRepeatsInTheSameOrder(kind: SpatialIndex.Kind) {
        let points = SpatialIndexTests.sets()[0].points
        let index = SpatialIndex(points, kind: kind)
        func walk() -> [Int] {
            var seen: [Int] = []
            index.forEachNeighbor(of: Vector2(300, 300), within: 90) { i, _ in seen.append(i) }
            return seen
        }
        let first = walk()
        #expect(walk() == first)
        #expect(first.sorted() == index.neighbors(of: Vector2(300, 300), within: 90))
        // The squared distance handed to the closure is the real one.
        index.forEachNeighbor(of: Vector2(300, 300), within: 90) { i, d2 in
            #expect(abs(d2 - points[i].distanceSquared(to: Vector2(300, 300))) < 1e-9)
        }
    }

    /// Cells are cut on the lattice that runs through the origin, so the same
    /// cell size sorts a point into the same cell whatever else is in the set.
    /// Without that, a set rebuilt after its points moved walks its neighbors in
    /// a different order, and a sum over them drifts in its last digits.
    @Test
    func theCellsStayWhereTheyAreWhenTheSetChanges() {
        let core = [Vector2(101, 101), Vector2(109, 133), Vector2(140, 118),
                    Vector2(96, 150), Vector2(133, 96)]
        func walk(_ points: [Vector2]) -> [Int] {
            let index = SpatialIndex(points, cellSize: 20)
            var seen: [Int] = []
            index.forEachNeighbor(of: Vector2(120, 120), within: 20) { i, _ in seen.append(i) }
            return seen
        }
        let alone = walk(core)
        #expect(!alone.isEmpty)
        // A point far away moves the set's own corner, and must not move a cell.
        #expect(walk(core + [Vector2(-4000, 5000)]) == alone)
        #expect(walk(core + [Vector2(2317, -913)]) == alone)
    }

    /// Being near is a two-way relation: if j is within reach of i, then i is
    /// within reach of j. Asking it of every point of a large set is the test
    /// that would not finish at all if the index were secretly reading every
    /// point for every query, and it catches a walk that misses a cell only on
    /// one side.
    @Test(arguments: [SpatialIndex.Kind.grid, .tree])
    func beingNearIsATwoWayRelationAcrossALargeSet(kind: SpatialIndex.Kind) {
        var points: [Vector2] = []
        var state: UInt64 = 0xDEADBEEF
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        for _ in 0 ..< 8000 { points.append(Vector2(next() * 600, next() * 600)) }
        let index = SpatialIndex(points, kind: kind)
        var near = [Set<Int>](repeating: [], count: points.count)
        for i in points.indices {
            index.forEachNeighbor(of: i, within: 20) { j, _ in near[i].insert(j) }
        }
        var pairs = 0
        for i in points.indices {
            for j in near[i] {
                #expect(near[j].contains(i), "\(i) sees \(j) but not the other way")
                pairs += 1
            }
        }
        #expect(pairs > 100_000, "the probe radius found almost nothing to check")
    }
}
