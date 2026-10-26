import Foundation
import Ollin
import Testing

/// Pure-CPU checks on `SpatialIndex3D`, the twin of `SpatialIndexTests` in
/// space: whatever the index says, a plain loop over every point has to say
/// the same thing, index for index and in the same order, for both kinds, over
/// point sets picked to be awkward (clumped, on a plane, along a line, piled on
/// one spot), from query points inside the set and far outside it. No GPU.
@Suite
struct SpatialIndex3DTests {

    // MARK: - The brute-force answers

    static func bruteNearest(_ points: [Vector3], _ p: Vector3) -> Int? {
        var best = -1, bestD2 = Double.infinity
        for i in points.indices {
            let d2 = points[i].distanceSquared(to: p)
            if best < 0 || d2 < bestD2 || (d2 == bestD2 && i < best) { bestD2 = d2; best = i }
        }
        return best >= 0 ? best : nil
    }

    static func bruteKNearest(_ points: [Vector3], _ k: Int, _ p: Vector3) -> [Int] {
        var ranked: [(d2: Double, i: Int)] = []
        for i in points.indices { ranked.append((points[i].distanceSquared(to: p), i)) }
        ranked.sort { $0.d2 != $1.d2 ? $0.d2 < $1.d2 : $0.i < $1.i }
        let want: Int = Swift.min(k, points.count)
        var answer: [Int] = []
        for entry in ranked.prefix(want) { answer.append(entry.i) }
        return answer
    }

    static func bruteNeighbors(_ points: [Vector3], _ p: Vector3, _ radius: Double) -> [Int] {
        points.indices.filter { points[$0].distanceSquared(to: p) <= radius * radius }
    }

    static func bruteRegion(_ points: [Vector3], _ box: Box3) -> [Int] {
        points.indices.filter {
            let q = points[$0]
            return q.x >= box.min.x && q.x <= box.max.x && q.y >= box.min.y && q.y <= box.max.y
                && q.z >= box.min.z && q.z <= box.max.z
        }
    }

    // MARK: - The awkward point sets

    struct Dice {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
    }

    static func sets() -> [(name: String, points: [Vector3])] {
        var dice = Dice(state: 0x9E3779B97F4A7C15)
        var uniform: [Vector3] = [], clumped: [Vector3] = []
        var plane: [Vector3] = [], line: [Vector3] = [], piled: [Vector3] = []
        for _ in 0 ..< 600 { uniform.append(Vector3(dice.next() * 600, dice.next() * 600, dice.next() * 600)) }
        for c in 0 ..< 8 {                       // eight tight clumps at the corners of a cube
            let center = Vector3(60 + Double(c % 2) * 400, 60 + Double((c / 2) % 2) * 400,
                                 60 + Double(c / 4) * 400)
            for _ in 0 ..< 40 {
                clumped.append(center + Vector3(dice.next() * 8 - 4, dice.next() * 8 - 4, dice.next() * 8 - 4))
            }
        }
        for _ in 0 ..< 300 { plane.append(Vector3(dice.next() * 600, dice.next() * 600, 250)) }  // no depth
        for i in 0 ..< 200 { line.append(Vector3(Double(i) * 3, 250, 250)) }                       // one axis
        for _ in 0 ..< 60 { piled.append(Vector3(100, 100, 100)) }                                  // one spot
        return [("uniform", uniform), ("clumped", clumped), ("plane", plane),
                ("line", line), ("piled", piled),
                ("one", [Vector3(30, 40, 50)]), ("none", [])]
    }

    static func probes(_ points: [Vector3]) -> [Vector3] {
        var probes = [Vector3(300, 300, 300), Vector3(0, 0, 0), Vector3(-500, -500, -500),
                      Vector3(1200, 300, 300), Vector3(300, -800, 300), Vector3(300, 300, 900),
                      Vector3(-40, 610, 250), Vector3(100, 100, 100)]
        if let first = points.first { probes.append(first) }
        if points.count > 7 { probes.append(points[7]) }
        return probes
    }

    static let regions = [Box3(min: Vector3(100, 100, 100), max: Vector3(300, 250, 400)),
                          Box3(min: Vector3(-50, -50, -50), max: Vector3(-10, -10, -10)),
                          Box3(min: .zero, max: Vector3(2000, 2000, 2000)),
                          Box3(min: Vector3(100, 100, 100), max: Vector3(100, 100, 100)),
                          Box3(min: Vector3(0, 240, 0), max: Vector3(600, 260, 600))]

    // MARK: - The invariant

    @Test(arguments: [SpatialIndex3D.Kind.grid, .tree])
    func everyQueryAgreesWithAPlainLoop(kind: SpatialIndex3D.Kind) {
        for set in SpatialIndex3DTests.sets() {
            let index = SpatialIndex3D(set.points, kind: kind)
            #expect(index.count == set.points.count, "\(set.name)")
            for p in SpatialIndex3DTests.probes(set.points) {
                let where_ = "\(set.name)/\(kind)/\(p)"
                #expect(index.nearest(to: p) == SpatialIndex3DTests.bruteNearest(set.points, p),
                        "nearest \(where_)")
                for k in [1, 3, 7, 40] {
                    #expect(index.kNearest(k, to: p)
                            == SpatialIndex3DTests.bruteKNearest(set.points, k, p),
                            "kNearest \(k) \(where_)")
                }
                for r in [0.5, 5.0, 30.0, 200.0] {
                    let all = SpatialIndex3DTests.bruteNeighbors(set.points, p, r)
                    #expect(index.neighbors(of: p, within: r) == all, "neighbors \(r) \(where_)")
                    if let any = index.anyNeighbor(of: p, within: r) {
                        #expect(all.contains(any), "anyNeighbor \(r) \(where_)")
                    } else {
                        #expect(all.isEmpty, "anyNeighbor \(r) \(where_)")
                    }
                    #expect(index.hasNeighbor(of: p, within: r) == !all.isEmpty, "hasNeighbor \(r) \(where_)")
                }
            }
            for region in SpatialIndex3DTests.regions {
                #expect(index.indices(in: region) == SpatialIndex3DTests.bruteRegion(set.points, region),
                        "region \(set.name)/\(kind)")
            }
        }
    }

    @Test
    func theAnswerDoesNotDependOnTheCellSize() {
        let points = SpatialIndex3DTests.sets()[0].points
        let reference = SpatialIndex3D(points)
        for size in [0.5, 7.0, 61.0, 5000.0] {
            let index = SpatialIndex3D(points, cellSize: size)
            for p in SpatialIndex3DTests.probes(points).prefix(4) {
                #expect(index.nearest(to: p) == reference.nearest(to: p), "cell \(size)")
                #expect(index.kNearest(5, to: p) == reference.kNearest(5, to: p), "cell \(size)")
                #expect(index.neighbors(of: p, within: 40) == reference.neighbors(of: p, within: 40),
                        "cell \(size)")
            }
        }
    }

    @Test(arguments: [SpatialIndex3D.Kind.grid, .tree])
    func equalDistancesAnswerWithTheLowerIndex(kind: SpatialIndex3D.Kind) {
        let points = (0 ..< 40).map { _ in Vector3(200, 200, 200) } + [Vector3(500, 500, 500)]
        let index = SpatialIndex3D(points, kind: kind)
        #expect(index.nearest(to: Vector3(210, 200, 200)) == 0)
        #expect(index.kNearest(3, to: Vector3(210, 200, 200)) == [0, 1, 2])
        // A point exactly between two others, on each axis in turn.
        for axis in 0 ..< 3 {
            func at(_ t: Double) -> Vector3 {
                axis == 0 ? Vector3(t, 100, 100) : (axis == 1 ? Vector3(100, t, 100) : Vector3(100, 100, t))
            }
            let between = SpatialIndex3D([at(100), at(300)], kind: kind)
            #expect(between.nearest(to: at(200)) == 0, "axis \(axis)")
            #expect(between.kNearest(2, to: at(200)) == [0, 1], "axis \(axis)")
        }
    }

    // MARK: - Growing a set

    @Test(arguments: [SpatialIndex3D.Kind.grid, .tree])
    func aGrowingIndexAgreesWithAPlainLoop(kind: SpatialIndex3D.Kind) {
        var index = SpatialIndex3D(bounds: Box3(min: .zero, max: Vector3(200, 200, 200)),
                                   cellSize: 20, kind: kind)
        var points: [Vector3] = []
        var dice = Dice(state: 12345)
        for step in 0 ..< 120 {
            // Half the points land outside the box it was built with.
            let spread = step < 60 ? 200.0 : 900.0
            let p = Vector3(dice.next() * spread - spread / 4, dice.next() * spread - spread / 4,
                            dice.next() * spread - spread / 4)
            let handed = index.insert(p)
            points.append(p)
            #expect(handed == points.count - 1)
            #expect(index.points == points)
            let probe = Vector3(dice.next() * 400 - 100, dice.next() * 400 - 100, dice.next() * 400 - 100)
            #expect(index.nearest(to: probe) == SpatialIndex3DTests.bruteNearest(points, probe), "step \(step)")
            #expect(index.neighbors(of: probe, within: 55)
                    == SpatialIndex3DTests.bruteNeighbors(points, probe, 55), "step \(step)")
        }
        #expect(index.count == 120)
    }

    @Test(arguments: [SpatialIndex3D.Kind.grid, .tree])
    func thePointItselfIsLeftOut(kind: SpatialIndex3D.Kind) {
        let points = SpatialIndex3DTests.sets()[1].points   // the clumped set
        let index = SpatialIndex3D(points, kind: kind)
        for i in stride(from: 0, to: points.count, by: 17) {
            let expected = SpatialIndex3DTests.bruteNeighbors(points, points[i], 12).filter { $0 != i }
            #expect(index.neighbors(of: i, within: 12) == expected, "point \(i)")
        }
        let twins = SpatialIndex3D([Vector3(50, 50, 50), Vector3(50, 50, 50)], kind: kind)
        #expect(twins.neighbors(of: 0, within: 1) == [1])
        #expect(twins.neighbors(of: 1, within: 1) == [0])
    }

    @Test(arguments: [SpatialIndex3D.Kind.grid, .tree])
    func anEmptyIndexAnswersNothing(kind: SpatialIndex3D.Kind) {
        let index = SpatialIndex3D([], kind: kind)
        #expect(index.isEmpty)
        #expect(index.nearest(to: .zero) == nil)
        #expect(index.kNearest(4, to: .zero).isEmpty)
        #expect(index.neighbors(of: Vector3.zero, within: 100).isEmpty)
        #expect(index.anyNeighbor(of: .zero, within: 100) == nil)
        #expect(index.indices(in: Box3(min: Vector3(-1e6, -1e6, -1e6), max: Vector3(1e6, 1e6, 1e6))).isEmpty)
    }

    @Test
    func awkwardArgumentsAreRefusedQuietly() {
        let index = SpatialIndex3D([Vector3(10, 10, 10), Vector3(20, 20, 20)])
        #expect(index.kNearest(0, to: .zero).isEmpty)
        #expect(index.kNearest(-3, to: .zero).isEmpty)
        #expect(index.kNearest(99, to: .zero).count == 2)
        #expect(index.neighbors(of: Vector3.zero, within: -5).isEmpty)
        #expect(index.neighbors(of: 7, within: 5).isEmpty)
        // A coordinate this large squares into infinity: the tie rule decides,
        // and the answer is still a point.
        #expect(index.nearest(to: Vector3(1e300, -1e300, 1e300)) == 0)
    }

    @Test(arguments: [SpatialIndex3D.Kind.grid, .tree])
    func theWalkRepeatsInTheSameOrder(kind: SpatialIndex3D.Kind) {
        let points = SpatialIndex3DTests.sets()[0].points
        let index = SpatialIndex3D(points, kind: kind)
        let p = Vector3(300, 300, 300)
        func walk() -> [Int] {
            var seen: [Int] = []
            index.forEachNeighbor(of: p, within: 120) { i, _ in seen.append(i) }
            return seen
        }
        let first = walk()
        #expect(!first.isEmpty)
        #expect(walk() == first)
        #expect(first.sorted() == index.neighbors(of: p, within: 120))
        index.forEachNeighbor(of: p, within: 120) { i, d2 in
            #expect(abs(d2 - points[i].distanceSquared(to: p)) < 1e-9)
        }
    }

    /// Cells are cut on the lattice through the origin, so a far point cannot
    /// move the cells the others sit in, or the walk's order.
    @Test
    func theCellsStayWhereTheyAreWhenTheSetChanges() {
        let core = [Vector3(101, 101, 101), Vector3(109, 133, 112), Vector3(140, 118, 95),
                    Vector3(96, 150, 130), Vector3(133, 96, 118)]
        func walk(_ points: [Vector3]) -> [Int] {
            let index = SpatialIndex3D(points, cellSize: 20)
            var seen: [Int] = []
            index.forEachNeighbor(of: Vector3(120, 120, 115), within: 25) { i, _ in seen.append(i) }
            return seen
        }
        let alone = walk(core)
        #expect(!alone.isEmpty)
        #expect(walk(core + [Vector3(-4000, 5000, 700)]) == alone)
        #expect(walk(core + [Vector3(2317, -913, -2000)]) == alone)
    }

    /// Being near is a two-way relation over a large set: the test that would
    /// not finish if the index read every point for every query, and the one
    /// that catches a shell walk missing a face on one side.
    @Test(arguments: [SpatialIndex3D.Kind.grid, .tree])
    func beingNearIsATwoWayRelationAcrossALargeSet(kind: SpatialIndex3D.Kind) {
        var points: [Vector3] = []
        var dice = Dice(state: 0xDEADBEEF)
        for _ in 0 ..< 50_000 {
            points.append(Vector3(dice.next() * 600, dice.next() * 600, dice.next() * 600))
        }
        let index = SpatialIndex3D(points, kind: kind)
        var near = [[Int32]](repeating: [], count: points.count)
        for i in points.indices {
            index.forEachNeighbor(of: i, within: 20) { j, _ in near[i].append(Int32(j)) }
        }
        var pairs = 0
        var oneSided: [(i: Int, j: Int)] = []
        for i in points.indices {
            for j in near[i] {
                if !near[Int(j)].contains(Int32(i)) { oneSided.append((i, Int(j))) }
                pairs += 1
            }
        }
        let first = oneSided.first.map { "\($0.i) sees \($0.j) but not the other way" } ?? ""
        #expect(oneSided.isEmpty, "\(oneSided.count) pairs are near one way only: \(first)")
        #expect(pairs > 100_000, "the probe radius found almost nothing to check")
        // And a sample of those answers against the loop, on the large set.
        for i in stride(from: 0, to: points.count, by: 2500) {
            let expected = SpatialIndex3DTests.bruteNeighbors(points, points[i], 20).filter { $0 != i }
            #expect(near[i].map { Int($0) }.sorted() == expected, "point \(i)")
            #expect(index.kNearest(6, to: points[i]) == SpatialIndex3DTests.bruteKNearest(points, 6, points[i]))
        }
    }
}
