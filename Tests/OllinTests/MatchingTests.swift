import Foundation
import Ollin
import Testing

/// Pure-CPU checks on `Matching`. The statement is that `optimal` finds the
/// pairing with the least total cost: on sets small enough to try every
/// pairing, its total equals the best of all of them; on larger sets it never
/// costs more than the greedy rule, it is a proper pairing (no partner shared,
/// every element of the smaller set paired), and with distance as the cost no
/// two of its paths cross, which only the least-total pairing can promise.
/// No GPU.
@Suite
struct MatchingTests {

    struct Dice {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
    }

    static func points(_ count: Int, _ dice: inout Dice, over span: Double = 100) -> [Vector2] {
        (0 ..< count).map { _ in Vector2(dice.next() * span, dice.next() * span) }
    }

    /// The least total over every way of pairing `rows` rows with distinct
    /// columns of `table`, tried one by one. Only for a handful on a side.
    static func bruteLeastTotal(_ table: [[Double]]) -> Double {
        let rows = table.count, columns = table.first?.count ?? 0
        guard rows > 0, columns >= rows else { return 0 }
        var best = Double.infinity
        var taken = [Bool](repeating: false, count: columns)
        func place(_ row: Int, _ soFar: Double) {
            if row == rows { best = Swift.min(best, soFar); return }
            for j in 0 ..< columns where !taken[j] {
                taken[j] = true
                place(row + 1, soFar + table[row][j])
                taken[j] = false
            }
        }
        place(0, 0)
        return best
    }

    /// A pairing is proper when no element of either set appears twice and
    /// every element of the smaller set is paired.
    static func isProper(_ match: Matching) -> Bool {
        let firsts = match.pairs.map(\.first), seconds = match.pairs.map(\.second)
        return Set(firsts).count == match.pairs.count && Set(seconds).count == match.pairs.count
            && match.pairs.count == Swift.min(match.firstCount, match.secondCount)
            && firsts.allSatisfy { $0 >= 0 && $0 < match.firstCount }
            && seconds.allSatisfy { $0 >= 0 && $0 < match.secondCount }
            && firsts == firsts.sorted()
    }

    /// Whether two segments cross each other properly (at one interior point
    /// of both). Sharing an endpoint or touching at an endpoint does not count.
    static func cross(_ a: Vector2, _ b: Vector2, _ c: Vector2, _ d: Vector2) -> Bool {
        func side(_ p: Vector2, _ q: Vector2, _ r: Vector2) -> Double {
            (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
        }
        let s1 = side(a, b, c), s2 = side(a, b, d), s3 = side(c, d, a), s4 = side(c, d, b)
        return (s1 > 0) != (s2 > 0) && (s3 > 0) != (s4 > 0)
            && s1 != 0 && s2 != 0 && s3 != 0 && s4 != 0
    }

    // MARK: - The least total

    /// On every size up to eight on a side, square and not, the total equals
    /// the best of all pairings tried one by one.
    @Test
    func theTotalEqualsTheBestOfEveryPairingUpToEight() {
        var dice = Dice(state: 0x9E3779B97F4A7C15)
        for n in 1 ... 8 {
            for m in n ... 8 {
                for _ in 0 ..< 3 {
                    let a = MatchingTests.points(n, &dice), b = MatchingTests.points(m, &dice)
                    let table = a.map { p in b.map { p.distance(to: $0) } }
                    let best = MatchingTests.bruteLeastTotal(table)
                    let match = Matching.optimal(a, b)
                    #expect(abs(match.totalCost - best) < 1e-9, "\(n) by \(m): \(match.totalCost) vs \(best)")
                    #expect(MatchingTests.isProper(match), "\(n) by \(m)")
                    // The total reads off the pairs themselves.
                    let summed = match.pairs.reduce(0.0) { $0 + a[$1.first].distance(to: b[$1.second]) }
                    #expect(abs(summed - match.totalCost) < 1e-9)
                    // The other way round, the larger set first.
                    let flipped = Matching.optimal(b, a)
                    #expect(abs(flipped.totalCost - best) < 1e-9, "\(m) by \(n)")
                    #expect(MatchingTests.isProper(flipped))
                    // And the table form, with costs that are not distances.
                    let costs = (0 ..< n).map { _ in (0 ..< m).map { _ in (dice.next() * 20).rounded() } }
                    let tabled = Matching.optimal(costs: costs)
                    #expect(abs(tabled.totalCost - MatchingTests.bruteLeastTotal(costs)) < 1e-9, "table \(n) by \(m)")
                    #expect(MatchingTests.isProper(tabled))
                }
            }
        }
    }

    /// Larger sets: the optimal never costs more than the greedy rule, and it
    /// is a proper pairing, by distance and by a cost of the sketch's own.
    @Test
    func theOptimalNeverExceedsTheGreedy() {
        var dice = Dice(state: 77)
        for seed in 0 ..< 4 {
            let a = MatchingTests.points(300, &dice), b = MatchingTests.points(300, &dice)
            let optimal = Matching.optimal(a, b), greedy = Matching.greedy(a, b)
            #expect(MatchingTests.isProper(optimal) && MatchingTests.isProper(greedy), "seed \(seed)")
            #expect(optimal.totalCost <= greedy.totalCost + 1e-9, "seed \(seed)")
            #expect(optimal.totalCost < greedy.totalCost * 0.95,
                    "seed \(seed): the greedy total should be well above the least")
            // A cost of the sketch's own: match by size, the first set's radii
            // to the second's, with the difference as the cost.
            let sizes = (0 ..< 200).map { _ in dice.next() * 50 }
            let holes = (0 ..< 240).map { _ in dice.next() * 50 }
            let bySize = Matching.optimal(sizes, holes) { abs($0 - $1) }
            let greedyBySize = Matching.greedy(sizes, holes) { abs($0 - $1) }
            #expect(MatchingTests.isProper(bySize))
            #expect(bySize.totalCost <= greedyBySize.totalCost + 1e-9, "seed \(seed)")
            let summed = bySize.pairs.reduce(0.0) { $0 + abs(sizes[$1.first] - holes[$1.second]) }
            #expect(abs(summed - bySize.totalCost) < 1e-9)
        }
    }

    /// With distance as the cost, no two paths of the least-total pairing
    /// cross: uncrossing two that did would shorten the total.
    @Test
    func noTwoPathsCrossUnderTheDistanceCost() {
        var dice = Dice(state: 0xBEEF)
        let a = MatchingTests.points(300, &dice), b = MatchingTests.points(300, &dice)
        let match = Matching.optimal(a, b)
        var crossings = 0
        for (k, p) in match.pairs.enumerated() {
            for q in match.pairs[(k + 1)...]
            where MatchingTests.cross(a[p.first], b[p.second], a[q.first], b[q.second]) {
                crossings += 1
            }
        }
        #expect(crossings == 0, "\(crossings) pairs of paths cross")
        // The greedy pairing of the same sets does cross, which is the
        // picture the sketch shows.
        let greedy = Matching.greedy(a, b)
        var greedyCrossings = 0
        for (k, p) in greedy.pairs.enumerated() {
            for q in greedy.pairs[(k + 1)...]
            where MatchingTests.cross(a[p.first], b[p.second], a[q.first], b[q.second]) {
                greedyCrossings += 1
            }
        }
        #expect(greedyCrossings > 0)
    }

    // MARK: - Shapes of the sets

    @Test
    func unevenSetsPairTheSmallerOne() {
        var dice = Dice(state: 5)
        let few = MatchingTests.points(20, &dice), many = MatchingTests.points(50, &dice)
        let fewFirst = Matching.optimal(few, many)
        #expect(fewFirst.pairs.count == 20 && fewFirst.firstCount == 20 && fewFirst.secondCount == 50)
        #expect(MatchingTests.isProper(fewFirst))
        for i in 0 ..< 20 { #expect(fewFirst.partner(of: i) != nil) }
        #expect(fewFirst.partner(of: 20) == nil && fewFirst.partner(of: -1) == nil)
        let manyFirst = Matching.optimal(many, few)
        #expect(manyFirst.pairs.count == 20 && manyFirst.firstCount == 50)
        #expect(MatchingTests.isProper(manyFirst))
        #expect(abs(manyFirst.totalCost - fewFirst.totalCost) < 1e-9)
        #expect(manyFirst.pairs.filter { manyFirst.partner(of: $0.first) == $0.second }.count == 20)
        #expect((0 ..< 50).filter { manyFirst.partner(of: $0) == nil }.count == 30)
        // Reversed reads the same pairing from the other side.
        let back = manyFirst.reversed()
        #expect(back.firstCount == 20 && back.secondCount == 50)
        #expect(Set(back.pairs.map { Matching.Pair($0.second, $0.first) }) == Set(manyFirst.pairs))
        for pair in manyFirst.pairs { #expect(back.partner(of: pair.second) == pair.first) }
        #expect(back.reversed() == manyFirst)
    }

    @Test
    func emptySetsMatchNothing() {
        let some = [Vector2(1, 1), Vector2(2, 2)]
        for match in [Matching.optimal([], some), Matching.optimal(some, []), Matching.optimal([], [Vector2]())] {
            #expect(match.pairs.isEmpty && match.totalCost == 0)
            #expect(match.partner(of: 0) == nil)
        }
        #expect(Matching.optimal(costs: []).pairs.isEmpty)
        #expect(Matching.greedy([Vector2](), some).pairs.isEmpty)
    }

    /// The same input answers the same pairing, including a table of ties
    /// where many pairings share the least total.
    @Test
    func theSameInputAnswersTheSamePairing() {
        var dice = Dice(state: 9)
        let a = MatchingTests.points(120, &dice), b = MatchingTests.points(130, &dice)
        let first = Matching.optimal(a, b)
        #expect(Matching.optimal(a, b) == first)
        let tied = (0 ..< 30).map { i in (0 ..< 30).map { j in Double((i + j) % 3) } }
        let one = Matching.optimal(costs: tied)
        #expect(one == Matching.optimal(costs: tied))
        #expect(MatchingTests.isProper(one))
        #expect(one.totalCost == 0, "a zero on every row and column is reachable")
    }

    /// A cost that is infinite, or not a number, forbids the pair: it is never
    /// made, as many elements as the allowed pairs permit are still paired at
    /// the least total, and an element with no allowed partner is left out.
    @Test
    func aCostThatIsNotANumberForbidsThePair() {
        // A few forbidden pairs in a table that can still pair every row.
        var table = (0 ..< 6).map { _ in (0 ..< 6).map { _ in 1.0 } }
        table[0][0] = .infinity; table[1][1] = .nan; table[2][2] = -.infinity
        table[3][3] = 0.5; table[4][4] = 0.5
        let match = Matching.optimal(costs: table)
        #expect(MatchingTests.isProper(match))
        #expect(match.partner(of: 0) != 0 && match.partner(of: 1) != 1 && match.partner(of: 2) != 2)
        #expect(match.partner(of: 3) == 3 && match.partner(of: 4) == 4)
        #expect(abs(match.totalCost - 5) < 1e-9)

        // A row whose every pair is forbidden is left out, and the rest pair.
        table[5] = [Double](repeating: .infinity, count: 6)
        let fiveOfSix = Matching.optimal(costs: table)
        #expect(fiveOfSix.pairs.count == 5)
        #expect(fiveOfSix.partner(of: 5) == nil)
        #expect(Set(fiveOfSix.pairs.map(\.first)) == [0, 1, 2, 3, 4])
        #expect(abs(fiveOfSix.totalCost - 4) < 1e-9, "three at 1 and two at 0.5")

        // As many as can be paired come first, before the cost: row 0 alone
        // would take the cheap column, but that would strand row 1.
        let crowded = Matching.optimal(costs: [[1, 5], [2, .infinity]])
        #expect(crowded.pairs == [Matching.Pair(0, 1), Matching.Pair(1, 0)])
        #expect(abs(crowded.totalCost - 7) < 1e-9)

        // Nothing allowed pairs nothing, and the total stays zero.
        let hopeless = Matching.optimal([1.0, 2.0, 3.0], [1.0, 2.0]) { _, _ in Double.nan }
        #expect(hopeless.pairs.isEmpty && hopeless.totalCost == 0)
        #expect(hopeless.partner(of: 0) == nil)

        // A short row of the table forbids the pairs past its end.
        let ragged = Matching.optimal(costs: [[3], [1, 2]])
        #expect(ragged.pairs == [Matching.Pair(0, 0), Matching.Pair(1, 1)])

        // The greedy rule skips a forbidden pair and passes over an element
        // with nothing allowed left, pairing the ones after it.
        let greedy = Matching.greedy([0, 1, 2], [0, 1]) { i, j in i == 1 ? Double.infinity : Double(abs(i - j)) }
        #expect(greedy.pairs == [Matching.Pair(0, 0), Matching.Pair(2, 1)])
    }

    /// Points in space have the distance form too: a shifted copy of a cloud
    /// pairs every point with its own copy, so the total is the shift times
    /// the count.
    @Test
    func pointsInSpacePairByDistance() {
        var dice = Dice(state: 4)
        let cloud = (0 ..< 40).map { _ in Vector3(dice.next() * 10, dice.next() * 10, dice.next() * 10) }
        let shift = Vector3(0.1, -0.2, 0.3)
        let space = Matching.optimal(cloud, cloud.map { $0 + shift })
        #expect(MatchingTests.isProper(space))
        #expect(abs(space.totalCost - 40 * shift.length) < 1e-6)
        for pair in space.pairs { #expect(pair.first == pair.second) }
    }

    /// A matching built from pairs keeps the last pair for an element given
    /// two, and refuses pairs outside either set.
    @Test
    func pairsBuildAConsistentMatching() {
        let match = Matching(pairs: [Matching.Pair(0, 1), Matching.Pair(1, 1), Matching.Pair(2, 9),
                                     Matching.Pair(0, 2)],
                             totalCost: 3, firstCount: 3, secondCount: 3)
        #expect(match.pairs == [Matching.Pair(0, 2), Matching.Pair(1, 1)])
        #expect(match.partner(of: 0) == 2 && match.partner(of: 1) == 1 && match.partner(of: 2) == nil)
        #expect(match.reversed().partner(of: 2) == 0 && match.reversed().partner(of: 1) == 1)
    }
}
