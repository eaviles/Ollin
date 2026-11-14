import Foundation

/// A pairing between two sets, element by element, at the least total cost:
/// every element of the smaller set gets one partner in the other, no two
/// share a partner, and the sum of the costs over the pairs is the smallest
/// any such pairing can have.
///
/// ```swift
/// let match = Matching.optimal(particles, targets)        // cost: the distance
/// for pair in match.pairs {
///     particles[pair.first] = particles[pair.first].lerp(to: targets[pair.second], 0.05)
/// }
/// ```
///
/// This is the assignment problem. With distance as the cost, a cloud of
/// particles sent to a shape's points this way travels the least in total, and
/// no two paths cross. With a cost of your own, two palettes match color to
/// color, or a set of pieces matches a set of holes by size. The cost is any
/// closure over an element of each set.
///
/// `optimal` finds the pairing exactly, by the shortest-augmenting-path
/// method, which costs about the cube of the count: a few thousand on a side
/// takes a fraction of a second, and the cost of every pair is held in memory
/// while it runs. ``greedy(_:_:cost:)`` is the comparison: each element in turn
/// takes the cheapest partner still free, which is fast and often far from
/// the least total.
///
/// When the sets differ in size, every element of the smaller set is paired and
/// the rest of the larger set is left out. A cost that is infinite, or not a
/// number, forbids a pair outright, so a sketch keeps two things apart with one
/// line in the closure, and an element whose every pair is forbidden is left
/// out too. ``partner(of:)`` answers nil for an element of the first set that
/// found no partner.
public struct Matching: Equatable, Sendable {

    /// One pair: `first` indexes the first set, `second` the second.
    public struct Pair: Equatable, Hashable, Sendable {
        public let first: Int
        public let second: Int

        public init(_ first: Int, _ second: Int) {
            self.first = first
            self.second = second
        }
    }

    /// Every pair made, ascending by `first`.
    public let pairs: [Pair]

    /// The sum of the costs over the pairs.
    public let totalCost: Double

    /// How many elements the first set held.
    public let firstCount: Int

    /// How many elements the second set held.
    public let secondCount: Int

    /// Partner per element of the first set, -1 for none.
    private let partnerOfFirst: [Int]
    /// Partner per element of the second set, -1 for none.
    private let partnerOfSecond: [Int]

    /// A matching from its pairs. The pairs are kept sorted by `first`, and
    /// an element paired twice keeps its last pair.
    public init(pairs: [Pair], totalCost: Double, firstCount: Int, secondCount: Int) {
        var ofFirst = [Int](repeating: -1, count: Swift.max(firstCount, 0))
        var ofSecond = [Int](repeating: -1, count: Swift.max(secondCount, 0))
        for pair in pairs where ofFirst.indices.contains(pair.first)
            && ofSecond.indices.contains(pair.second) {
            if ofFirst[pair.first] >= 0 { ofSecond[ofFirst[pair.first]] = -1 }
            if ofSecond[pair.second] >= 0 { ofFirst[ofSecond[pair.second]] = -1 }
            ofFirst[pair.first] = pair.second
            ofSecond[pair.second] = pair.first
        }
        var kept: [Pair] = []
        for first in ofFirst.indices where ofFirst[first] >= 0 {
            kept.append(Pair(first, ofFirst[first]))
        }
        self.pairs = kept
        self.totalCost = totalCost
        self.firstCount = Swift.max(firstCount, 0)
        self.secondCount = Swift.max(secondCount, 0)
        self.partnerOfFirst = ofFirst
        self.partnerOfSecond = ofSecond
    }

    /// The index in the second set paired with element `first` of the first
    /// set, or nil when it has no partner (an index outside the first set, or
    /// a first set larger than the second).
    public func partner(of first: Int) -> Int? {
        guard partnerOfFirst.indices.contains(first), partnerOfFirst[first] >= 0 else { return nil }
        return partnerOfFirst[first]
    }

    /// The same pairing read from the other side: `first` indexes what was the
    /// second set, and `partner(of:)` answers for its elements.
    public func reversed() -> Matching {
        Matching(pairs: pairs.map { Pair($0.second, $0.first) }, totalCost: totalCost,
                 firstCount: secondCount, secondCount: firstCount)
    }

    // MARK: - Finding one

    // The finders and the solver under them are inlinable on purpose. A host
    // compiles a sketch optimized whatever the framework it carries was built
    // as, and with the bodies visible that compile makes its own copy for the
    // sketch's types and its cost closure, so a pairing runs at the speed of
    // an optimized build under a debug host. The point forms are forced inline
    // as well: left to the optimizer, the greedy one stayed a call into the
    // framework and ran forty times slower there.

    /// The pairing of `first` with `second` at the least total `cost`.
    ///
    /// A cost that is infinite, or not a number, **forbids** the pair: those
    /// two are never paired. The matching then pairs as many elements as the
    /// allowed pairs permit, at the least total cost among those, and an
    /// element with no allowed partner is left out, so ``partner(of:)`` answers
    /// nil for it. Among pairings of equal total cost the one answered is
    /// fixed, so a seeded sketch reproduces.
    @inlinable
    public static func optimal<A, B>(_ first: [A], _ second: [B],
                                     cost: (A, B) -> Double) -> Matching {
        let n = first.count, m = second.count
        guard n > 0, m > 0 else {
            return Matching(pairs: [], totalCost: 0, firstCount: n, secondCount: m)
        }
        // The solver wants no more rows than columns, so the larger set plays
        // the columns and the answer is read back the right way round.
        let transposed = n > m
        let rows = transposed ? m : n, columns = transposed ? n : m
        var table = [Double](repeating: 0, count: rows * columns)
        var forbidden = [Bool](repeating: false, count: rows * columns)
        var largest = 0.0
        for i in 0 ..< rows {
            for j in 0 ..< columns {
                let c = transposed ? cost(first[j], second[i]) : cost(first[i], second[j])
                if c.isFinite {
                    table[i * columns + j] = c
                    if c > largest { largest = c }
                } else {
                    forbidden[i * columns + j] = true
                }
            }
        }
        // A forbidden pair costs more than every allowed pair together, so the
        // solver makes as few of them as it can before it minds the rest, and
        // the ones it still had to make are dropped afterwards. The stand-in
        // stays within a few digits of the real costs, which keeps the solver's
        // arithmetic exact where it matters.
        let standIn = (largest + 1) * Double(rows + 1)
        for k in table.indices where forbidden[k] { table[k] = standIn }
        let columnOfRow = solve(rows: rows, columns: columns, table)
        var pairs: [Pair] = []
        pairs.reserveCapacity(rows)
        var total = 0.0
        for i in 0 ..< rows {
            let j = columnOfRow[i]
            guard j >= 0, !forbidden[i * columns + j] else { continue }
            total += table[i * columns + j]
            pairs.append(transposed ? Pair(j, i) : Pair(i, j))
        }
        return Matching(pairs: pairs, totalCost: total, firstCount: n, secondCount: m)
    }

    /// The pairing of two point sets at the least total distance.
    @inlinable @inline(__always)
    public static func optimal(_ first: [Vector2], _ second: [Vector2]) -> Matching {
        optimal(first, second) { $0.distance(to: $1) }
    }

    /// The pairing of two point sets in space at the least total distance.
    @inlinable @inline(__always)
    public static func optimal(_ first: [Vector3], _ second: [Vector3]) -> Matching {
        optimal(first, second) { $0.distance(to: $1) }
    }

    /// The pairing at the least total cost over a table of costs, one row per
    /// element of the first set and one column per element of the second. A
    /// short row forbids the pairs past its end.
    public static func optimal(costs: [[Double]]) -> Matching {
        let columns = costs.map(\.count).max() ?? 0
        return optimal(Array(costs.indices), Array(0 ..< columns)) { i, j in
            j < costs[i].count ? costs[i][j] : .infinity
        }
    }

    /// The comparison: each element of `first` in turn takes the cheapest
    /// partner in `second` still free. Fast, and not the least total. A cost
    /// that is infinite, or not a number, forbids the pair here too, and an
    /// element with no allowed partner left is passed over.
    @inlinable
    public static func greedy<A, B>(_ first: [A], _ second: [B],
                                    cost: (A, B) -> Double) -> Matching {
        let n = first.count, m = second.count
        var taken = [Bool](repeating: false, count: m)
        var pairs: [Pair] = []
        var total = 0.0
        for i in 0 ..< n {
            var best = -1, bestCost = Double.infinity
            for j in 0 ..< m where !taken[j] {
                let c = cost(first[i], second[j])
                guard c.isFinite else { continue }
                if best < 0 || c < bestCost { best = j; bestCost = c }
            }
            guard best >= 0 else { continue }
            taken[best] = true
            pairs.append(Pair(i, best))
            total += bestCost
        }
        return Matching(pairs: pairs, totalCost: total, firstCount: n, secondCount: m)
    }

    /// The pairing of two point sets by the greedy rule, by distance.
    @inlinable @inline(__always)
    public static func greedy(_ first: [Vector2], _ second: [Vector2]) -> Matching {
        greedy(first, second) { $0.distance(to: $1) }
    }

    // MARK: - The solver

    /// The shortest-augmenting-path assignment over a `rows` by `columns` table
    /// with no more rows than columns. Answers the column of every row.
    ///
    /// Each row in turn is given a column by growing a shortest path from it
    /// through the columns already taken, measured in the reduced costs the
    /// dual variables `u` and `v` keep, and the path is then flipped so every
    /// row on it keeps a column and the new row has one. Every row keeps the
    /// column it has unless a cheaper total moves it, so the assignment after
    /// the last row is the least total over the whole table.
    ///
    /// The walk reads and writes raw memory in `while` loops on purpose. The
    /// scan of the remaining columns runs about the cube of the count, and in
    /// a build with no optimization every array read is a call and every step
    /// of a `for` over a range is another, which made 1,600 points take twelve
    /// seconds where this form takes under one (and two thirds of the time in
    /// an optimized build). Every index is one the loops' own bounds keep
    /// inside its buffer: `k` below `rows` or `columns`, `j` a column out of
    /// `remaining`, and a row out of `rowOfColumn` only where a row was stored.
    @inlinable
    static func solve(rows: Int, columns: Int, _ costs: [Double]) -> [Int] {
        precondition(rows >= 0 && rows <= columns && costs.count >= rows * columns)
        let u = UnsafeMutablePointer<Double>.allocate(capacity: rows)
        let v = UnsafeMutablePointer<Double>.allocate(capacity: columns)
        let shortest = UnsafeMutablePointer<Double>.allocate(capacity: columns)
        let path = UnsafeMutablePointer<Int>.allocate(capacity: columns)
        let columnOfRow = UnsafeMutablePointer<Int>.allocate(capacity: rows)
        let rowOfColumn = UnsafeMutablePointer<Int>.allocate(capacity: columns)
        let rowSeen = UnsafeMutablePointer<Bool>.allocate(capacity: rows)
        let columnSeen = UnsafeMutablePointer<Bool>.allocate(capacity: columns)
        let remaining = UnsafeMutablePointer<Int>.allocate(capacity: columns)
        defer {
            u.deallocate(); v.deallocate(); shortest.deallocate(); path.deallocate()
            columnOfRow.deallocate(); rowOfColumn.deallocate(); rowSeen.deallocate()
            columnSeen.deallocate(); remaining.deallocate()
        }
        u.initialize(repeating: 0, count: rows)
        v.initialize(repeating: 0, count: columns)
        shortest.initialize(repeating: .infinity, count: columns)
        path.initialize(repeating: -1, count: columns)
        columnOfRow.initialize(repeating: -1, count: rows)
        rowOfColumn.initialize(repeating: -1, count: columns)
        rowSeen.initialize(repeating: false, count: rows)
        columnSeen.initialize(repeating: false, count: columns)
        remaining.initialize(repeating: 0, count: columns)

        costs.withUnsafeBufferPointer { table in
            guard let cost = table.baseAddress else { return }
            var current = 0
            while current < rows {
                var minValue = 0.0
                var i = current
                var remainingCount = columns
                var k = 0
                while k < columns {
                    remaining[k] = columns - k - 1
                    columnSeen[k] = false
                    shortest[k] = .infinity
                    k += 1
                }
                k = 0
                while k < rows {
                    rowSeen[k] = false
                    k += 1
                }
                var sink = -1
                while sink < 0 {
                    var at = -1
                    var lowest = Double.infinity
                    rowSeen[i] = true
                    let row = cost + i * columns
                    let ui = u[i]
                    k = 0
                    while k < remainingCount {
                        let j = remaining[k]
                        let reduced = minValue + row[j] - ui - v[j]
                        var reach = shortest[j]
                        if reduced < reach {
                            path[j] = i
                            shortest[j] = reduced
                            reach = reduced
                        }
                        // Among equal costs, prefer a column still free, which
                        // ends the path now rather than growing it through a tie.
                        if reach < lowest || (reach == lowest && rowOfColumn[j] < 0) {
                            lowest = reach
                            at = k
                        }
                        k += 1
                    }
                    minValue = lowest
                    if at < 0 { return }   // every cost infinite: cannot happen with finite costs
                    let j = remaining[at]
                    if rowOfColumn[j] < 0 { sink = j } else { i = rowOfColumn[j] }
                    columnSeen[j] = true
                    remainingCount -= 1
                    remaining[at] = remaining[remainingCount]
                }
                // Move the duals so every reduced cost on the path reads zero.
                u[current] += minValue
                k = 0
                while k < rows {
                    if rowSeen[k] && k != current { u[k] += minValue - shortest[columnOfRow[k]] }
                    k += 1
                }
                k = 0
                while k < columns {
                    if columnSeen[k] { v[k] -= minValue - shortest[k] }
                    k += 1
                }
                // Flip the path: every row on it takes the next column along.
                var j = sink
                while true {
                    let row = path[j]
                    rowOfColumn[j] = row
                    let previous = columnOfRow[row]
                    columnOfRow[row] = j
                    j = previous
                    if row == current { break }
                }
                current += 1
            }
        }
        return Array(UnsafeBufferPointer(start: columnOfRow, count: rows))
    }
}
