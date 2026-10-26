import Foundation
import Ollin
import Testing

/// Pure-CPU checks on `BoundsIndex`. The invariant is the one `SpatialIndex`
/// is held to: the index is only a faster way to ask a question with one right
/// answer, so whatever it says, a plain loop over every box has to say the
/// same, index for index and pair for pair. The oracle below spells the
/// interval tests out rather than calling `Rectangle.intersects`, so the two
/// sides cannot share a mistake. No GPU.
@Suite
struct BoundsIndexTests {

    // MARK: - The brute-force answers

    static func holds(_ b: Rectangle, _ p: Vector2) -> Bool {
        p.x >= b.x && p.x <= b.x + b.width && p.y >= b.y && p.y <= b.y + b.height
    }

    static func overlap(_ a: Rectangle, _ b: Rectangle) -> Bool {
        a.x <= b.x + b.width && b.x <= a.x + a.width
            && a.y <= b.y + b.height && b.y <= a.y + a.height
    }

    static func bruteContaining(_ boxes: [Rectangle], _ p: Vector2) -> [Int] {
        boxes.indices.filter { holds(boxes[$0], p) }
    }

    static func bruteOverlapping(_ boxes: [Rectangle], _ region: Rectangle) -> [Int] {
        boxes.indices.filter { overlap(boxes[$0], region) }
    }

    static func brutePairs(_ boxes: [Rectangle]) -> [BoundsIndex.Pair] {
        var pairs: [BoundsIndex.Pair] = []
        for i in boxes.indices {
            for j in (i + 1) ..< boxes.count where overlap(boxes[i], boxes[j]) {
                pairs.append(BoundsIndex.Pair(i, j))
            }
        }
        return pairs
    }

    static func brutePairs(_ a: [Rectangle], _ b: [Rectangle]) -> [BoundsIndex.Pair] {
        var pairs: [BoundsIndex.Pair] = []
        for i in a.indices {
            for j in b.indices where overlap(a[i], b[j]) { pairs.append(BoundsIndex.Pair(i, j)) }
        }
        return pairs
    }

    // MARK: - The awkward box sets

    /// A plain deterministic generator, no framework.
    struct Dice {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
    }

    static func randomBoxes(_ count: Int, over span: Double, size: ClosedRange<Double>,
                            seed: UInt64) -> [Rectangle] {
        var dice = Dice(state: seed)
        var boxes: [Rectangle] = []
        for _ in 0 ..< count {
            let w = size.lowerBound + dice.next() * (size.upperBound - size.lowerBound)
            let h = size.lowerBound + dice.next() * (size.upperBound - size.lowerBound)
            boxes.append(Rectangle(x: dice.next() * span, y: dice.next() * span, width: w, height: h))
        }
        return boxes
    }

    /// Named box sets, each shaped to break a different assumption.
    static func sets() -> [(name: String, boxes: [Rectangle])] {
        let uniform = randomBoxes(500, over: 600, size: 4 ... 40, seed: 0x9E3779B97F4A7C15)
        var clumped: [Rectangle] = []
        var dice = Dice(state: 77)
        for c in 0 ..< 6 {                      // six tight clumps, wide gaps
            let center = Vector2(60 + Double(c % 3) * 250, 60 + Double(c / 3) * 400)
            for _ in 0 ..< 40 {
                clumped.append(Rectangle(x: center.x + dice.next() * 10 - 5,
                                         y: center.y + dice.next() * 10 - 5,
                                         width: 2 + dice.next() * 6, height: 2 + dice.next() * 6))
            }
        }
        // A row of boxes that share their edges exactly, so every neighbor
        // touches and touching has to count.
        let row = (0 ..< 120).map { Rectangle(x: Double($0) * 5, y: 250, width: 5, height: 5) }
        // Every box the same: every pair overlaps, every point is in all or none.
        let piled = (0 ..< 60).map { _ in Rectangle(x: 100, y: 100, width: 30, height: 20) }
        // Boxes with no area, which still hold the points on their line.
        let flat = (0 ..< 50).map { Rectangle(x: Double($0) * 11, y: 300, width: 0, height: 40) }
        // A few wide boxes over many small ones: the tree's halves overlap a lot.
        var mixed = randomBoxes(300, over: 600, size: 2 ... 12, seed: 5)
        mixed += randomBoxes(8, over: 600, size: 150 ... 400, seed: 6)
        return [("uniform", uniform), ("clumped", clumped), ("row", row),
                ("piled", piled), ("flat", flat), ("mixed", mixed),
                ("one", [Rectangle(x: 30, y: 40, width: 10, height: 10)]), ("none", [])]
    }

    static func probes(_ boxes: [Rectangle]) -> [Vector2] {
        var probes = [Vector2(300, 300), Vector2(0, 0), Vector2(-500, -500),
                      Vector2(1200, 300), Vector2(100, 100), Vector2(252.5, 250),
                      Vector2(255, 250), Vector2(22, 320)]
        if let first = boxes.first {
            probes.append(first.corner)                       // a corner, on the boundary
            probes.append(first.center)
            probes.append(Vector2(first.x + first.width, first.y + first.height / 2))   // an edge
        }
        return probes
    }

    static let regions = [Rectangle(x: 100, y: 100, width: 200, height: 150),
                          Rectangle(x: -50, y: -50, width: 40, height: 40),
                          Rectangle(x: 0, y: 0, width: 2000, height: 2000),
                          Rectangle(x: 100, y: 100, width: 0, height: 0),
                          Rectangle(x: 130, y: 120, width: 1, height: 1),
                          Rectangle(x: 600, y: 250, width: 10, height: 5)]

    // MARK: - The invariant

    @Test
    func everyQueryAgreesWithAPlainLoop() {
        for set in BoundsIndexTests.sets() {
            let index = BoundsIndex(set.boxes)
            #expect(index.count == set.boxes.count, "\(set.name)")
            for p in BoundsIndexTests.probes(set.boxes) {
                #expect(index.indices(containing: p)
                        == BoundsIndexTests.bruteContaining(set.boxes, p),
                        "containing \(set.name) \(p)")
            }
            for region in BoundsIndexTests.regions {
                #expect(index.indices(overlapping: region)
                        == BoundsIndexTests.bruteOverlapping(set.boxes, region),
                        "overlapping \(set.name) \(region)")
            }
            #expect(index.overlappingPairs() == BoundsIndexTests.brutePairs(set.boxes),
                    "pairs \(set.name)")
        }
    }

    /// The pairs across two sets, in both directions.
    @Test
    func pairsAcrossTwoSetsAgreeWithAPlainLoop() {
        let a = BoundsIndexTests.randomBoxes(1500, over: 600, size: 3 ... 30, seed: 11)
        let b = BoundsIndexTests.randomBoxes(1200, over: 600, size: 3 ... 30, seed: 12)
        let ia = BoundsIndex(a), ib = BoundsIndex(b)
        #expect(ia.overlappingPairs(with: ib) == BoundsIndexTests.brutePairs(a, b))
        #expect(ib.overlappingPairs(with: ia) == BoundsIndexTests.brutePairs(b, a))
        // Against itself, the cross form reports every ordered pair that
        // overlaps, the box with itself included.
        let selfPairs = ia.overlappingPairs(with: ia)
        #expect(selfPairs == BoundsIndexTests.brutePairs(a, a))
        #expect(ia.overlappingPairs(with: BoundsIndex([])).isEmpty)
    }

    /// Thousands of boxes, every pair found, and the answers equal the loop.
    /// This is the test that would not finish in time if the index were
    /// secretly reading every box for every box.
    @Test
    func aLargeSetAnswersEveryPairExactly() {
        let boxes = BoundsIndexTests.randomBoxes(10_000, over: 2000, size: 2 ... 24, seed: 99)
        let index = BoundsIndex(boxes)
        let pairs = index.overlappingPairs()
        #expect(pairs == BoundsIndexTests.brutePairs(boxes))
        #expect(pairs.count > 2000, "the sizes found almost nothing to check")
        var dice = Dice(state: 3)
        for _ in 0 ..< 200 {
            let p = Vector2(dice.next() * 2200 - 100, dice.next() * 2200 - 100)
            #expect(index.indices(containing: p) == BoundsIndexTests.bruteContaining(boxes, p))
        }
    }

    // MARK: - Moving the boxes

    /// A refit index has to answer exactly as a fresh one, after a small drift
    /// (what a refit is for) and after a large one (still exact, only slower).
    @Test
    func aRefitIndexAnswersAsARebuiltOne() {
        let boxes = BoundsIndexTests.randomBoxes(800, over: 600, size: 4 ... 30, seed: 21)
        var index = BoundsIndex(boxes)
        var dice = Dice(state: 8)
        var moved = boxes
        for drift in [2.0, 20.0, 400.0] {
            moved = moved.map {
                Rectangle(x: $0.x + (dice.next() - 0.5) * drift, y: $0.y + (dice.next() - 0.5) * drift,
                          width: $0.width, height: $0.height)
            }
            index.refit(to: moved)
            #expect(index.boxes == moved)
            let fresh = BoundsIndex(moved)
            #expect(index.overlappingPairs() == fresh.overlappingPairs(), "drift \(drift)")
            #expect(index.overlappingPairs() == BoundsIndexTests.brutePairs(moved), "drift \(drift)")
            for p in BoundsIndexTests.probes(moved) {
                #expect(index.indices(containing: p)
                        == BoundsIndexTests.bruteContaining(moved, p), "drift \(drift) \(p)")
            }
            for region in BoundsIndexTests.regions {
                #expect(index.indices(overlapping: region)
                        == BoundsIndexTests.bruteOverlapping(moved, region), "drift \(drift)")
            }
        }
        // A different count cannot be refit, so it rebuilds, and still answers.
        let fewer = Array(moved.prefix(300))
        index.refit(to: fewer)
        #expect(index.count == 300)
        #expect(index.overlappingPairs() == BoundsIndexTests.brutePairs(fewer))
    }

    // MARK: - Edges, order, and the empty case

    /// Touching counts, on both sides of the rule, matching `Rectangle`.
    @Test
    func touchingBoxesOverlapAndTheBoundaryIsInside() {
        let a = Rectangle(x: 0, y: 0, width: 10, height: 10)
        let b = Rectangle(x: 10, y: 0, width: 10, height: 10)      // shares an edge
        let c = Rectangle(x: 10, y: 10, width: 10, height: 10)     // shares a corner with a
        let d = Rectangle(x: 10.001, y: 0, width: 10, height: 10)  // just apart from a
        #expect(a.intersects(b) && a.intersects(c) && !a.intersects(d))
        #expect(a.intersection(b) == Rectangle(x: 10, y: 0, width: 0, height: 10))
        #expect(a.intersection(d) == nil)
        #expect(a.union(c) == Rectangle(x: 0, y: 0, width: 20, height: 20))
        let index = BoundsIndex([a, b, c, d])
        #expect(index.overlappingPairs() == [BoundsIndex.Pair(0, 1), BoundsIndex.Pair(0, 2),
                                             BoundsIndex.Pair(1, 2), BoundsIndex.Pair(1, 3),
                                             BoundsIndex.Pair(2, 3)])
        #expect(index.indices(containing: Vector2(10, 5)) == [0, 1])
        #expect(index.indices(containing: Vector2(10, 10)) == [0, 1, 2])
        #expect(index.indices(overlapping: Rectangle(x: 20, y: 20, width: 5, height: 5)) == [2])
        // Past c's edge at 20 but within d's at 20.001, touching d at its bottom.
        #expect(index.indices(overlapping: Rectangle(x: 20.0005, y: 10, width: 5, height: 5)) == [3])
        // At the corner (20, 10) b, c, and d all touch.
        #expect(index.indices(overlapping: Rectangle(x: 20, y: 10, width: 5, height: 5)) == [1, 2, 3])
        let all = index.bounds
        #expect(all?.x == 0 && all?.y == 0 && all?.height == 20)
        #expect(abs((all?.width ?? 0) - 20.001) < 1e-9)
    }

    @Test
    func anEmptyIndexAnswersNothing() {
        let index = BoundsIndex([])
        #expect(index.isEmpty)
        #expect(index.bounds == nil)
        #expect(index.indices(containing: .zero).isEmpty)
        #expect(index.indices(overlapping: Rectangle(x: -1e6, y: -1e6, width: 2e6, height: 2e6)).isEmpty)
        #expect(index.overlappingPairs().isEmpty)
        #expect(index.overlappingPairs(with: BoundsIndex([Rectangle(x: 0, y: 0, width: 1, height: 1)])).isEmpty)
        var grown = index
        grown.refit(to: [Rectangle(x: 0, y: 0, width: 5, height: 5)])
        #expect(grown.indices(containing: Vector2(2, 2)) == [0])
    }

    /// A box with a coordinate that is not a number never answers and never
    /// hides the boxes beside it.
    @Test
    func aBoxThatIsNotANumberIsLeftOut() {
        var boxes = BoundsIndexTests.randomBoxes(200, over: 400, size: 5 ... 30, seed: 4)
        boxes[17] = Rectangle(x: .nan, y: 20, width: 10, height: 10)
        boxes[90] = Rectangle(x: 50, y: 50, width: .nan, height: 10)
        let index = BoundsIndex(boxes)
        for p in BoundsIndexTests.probes(boxes) {
            let answer = index.indices(containing: p)
            #expect(answer == BoundsIndexTests.bruteContaining(boxes, p))
            #expect(!answer.contains(17) && !answer.contains(90))
        }
        #expect(index.overlappingPairs() == BoundsIndexTests.brutePairs(boxes))
    }

    /// The closure forms walk in a fixed order and find what the arrays find.
    @Test
    func theWalkRepeatsInTheSameOrder() {
        let boxes = BoundsIndexTests.randomBoxes(600, over: 600, size: 10 ... 80, seed: 31)
        let index = BoundsIndex(boxes)
        let p = Vector2(300, 300), region = Rectangle(x: 250, y: 250, width: 100, height: 100)
        func walkPoint() -> [Int] { var s: [Int] = []; index.forEachIndex(containing: p) { s.append($0) }; return s }
        func walkRegion() -> [Int] { var s: [Int] = []; index.forEachIndex(overlapping: region) { s.append($0) }; return s }
        let first = walkPoint(), second = walkRegion()
        #expect(!first.isEmpty && !second.isEmpty)
        #expect(walkPoint() == first)
        #expect(walkRegion() == second)
        #expect(first.sorted() == index.indices(containing: p))
        #expect(second.sorted() == index.indices(overlapping: region))
    }
}
