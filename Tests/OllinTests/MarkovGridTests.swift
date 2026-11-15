import Foundation
import Testing
import Ollin

/// The grid chain is a pure value, so it is checked by what it writes: against
/// the same chain written out by hand, against the counts it was shown, and
/// against twins that differ in one setting.
@Suite struct MarkovGridTests {

    // MARK: - The chain written out by hand

    /// The two-direction chain written out by hand, the way a sketch would
    /// write it without the type: a table from every prefix of a cell's four
    /// settled neighbors to a tally by value, a place off the sheet read as
    /// one value more, and a generator handed in. It is the independent
    /// statement of what `MarkovGrid` must write, cell for cell.
    /// `Recreations/HiroshiKawano/SimulatedColorMosaic` and `Flow` were tuned
    /// against exactly this arithmetic, so the two agreeing is what keeps
    /// those sketches where they are.
    private struct HandChain {
        let values: Int
        private(set) var counts: [[Int]: [Int]] = [:]

        init(values: Int) { self.values = values }

        func around(_ p: Int, in line: [Int], after before: [Int]?) -> [Int] {
            func value(_ cells: [Int]?, _ i: Int) -> Int {
                guard let cells, cells.indices.contains(i) else { return values }
                return cells[i]
            }
            return [value(line, p - 1), value(before, p), value(before, p - 1), value(before, p + 1)]
        }

        mutating func learn(_ lines: [[Int]]) {
            for (l, line) in lines.enumerated() {
                for (p, value) in line.enumerated() {
                    let cells = around(p, in: line, after: l > 0 ? lines[l - 1] : nil)
                    for n in 0 ... cells.count {
                        counts[Array(cells.prefix(n)), default: Array(repeating: 0, count: values)][value] += 1
                    }
                }
            }
        }

        /// The longest arrangement the data showed, starting from the whole one.
        func kept(_ cells: [Int]) -> [Int] {
            var cells = cells
            while counts[cells] == nil, !cells.isEmpty { cells.removeLast() }
            return cells
        }

        func line(after before: [Int]?, places: Int, using random: inout SplitMix64) -> [Int] {
            var line: [Int] = []
            for p in 0 ..< places {
                guard let tally = counts[kept(around(p, in: line, after: before))] else {
                    line.append(0)
                    continue
                }
                var roll = Int(random.next() % UInt64(tally.reduce(0, +)))
                var value = 0
                while roll >= tally[value] {
                    roll -= tally[value]
                    value += 1
                }
                line.append(value)
            }
            return line
        }
    }

    /// A data picture made by rule, so the test owns its data: fields of one
    /// value held in lines of value 1 on a ground of 0, or plain blocks of 1
    /// when there are only two values.
    private static func picture(side: Int, values: Int, seed: UInt64) -> [[Int]] {
        var random = SplitMix64(seed: seed)
        var cells = Array(repeating: Array(repeating: 0, count: side), count: side)
        for field in 0 ..< side / 3 {
            let w = 3 + Int(random.next() % UInt64(side / 3)), h = 3 + Int(random.next() % UInt64(side / 3))
            let x = Int(random.next() % UInt64(side - w)), y = Int(random.next() % UInt64(side - h))
            let inside = values > 2 ? 2 + field % (values - 2) : 1
            for row in y ..< y + h {
                for column in x ..< x + w {
                    let onLine = row == y || row == y + h - 1 || column == x || column == x + w - 1
                    cells[row][column] = onLine ? 1 : inside
                }
            }
        }
        return cells
    }

    private static func pictures(values: Int) -> [[[Int]]] {
        [picture(side: 40, values: values, seed: 11),
         picture(side: 40, values: values, seed: 12),
         picture(side: 32, values: values, seed: 13)]
    }

    /// Both sketches' output over six seeds, at their own two alphabets and at
    /// widths narrower and wider than the data. A sheet wider than its data
    /// meets arrangements the data never showed, so the forgetting is under
    /// the same check.
    @Test(arguments: [1, 2, 3, 4, 5, 6])
    func itWritesWhatTheHandWrittenChainWrote(seed: Int) throws {
        for values in [2, 5] {
            var hand = HandChain(values: values)
            var grid = MarkovGrid<Int>(vocabulary: Array(0 ..< values), seed: seed)
            for picture in Self.pictures(values: values) {
                hand.learn(picture)
                try grid.learn(picture)
            }
            for width in [24, 40, 100, 160] {
                var random = SplitMix64(seed: UInt64(bitPattern: Int64(seed)))
                var expected: [[Int]] = []
                var forgot = 0
                for _ in 0 ..< 120 {
                    let line = hand.line(after: expected.last, places: width, using: &random)
                    for p in line.indices {
                        let cells = hand.around(p, in: line, after: expected.last)
                        if hand.kept(cells).count < cells.count { forgot += 1 }
                    }
                    expected.append(line)
                }
                grid.reset()
                #expect(grid.nextRows(120, columns: width) == expected, "values \(values), width \(width)")
                if values == 5, width >= 100 { #expect(forgot > 0, "the wide sheet never met an unseen arrangement") }
            }
        }
    }

    /// The seed in the sketches is their variation, which can be anything.
    @Test func aNegativeOrLargeSeedIsTheSameGeneratorTheSketchesMade() throws {
        for seed in [0, -1, -7, Int.max, Int.min] {
            var hand = HandChain(values: 5)
            hand.learn(Self.picture(side: 40, values: 5, seed: 11))
            var grid = MarkovGrid<Int>(vocabulary: [0, 1, 2, 3, 4], seed: seed)
            try grid.learn(Self.picture(side: 40, values: 5, seed: 11))
            var random = SplitMix64(seed: UInt64(bitPattern: Int64(seed)))
            var expected: [[Int]] = []
            for _ in 0 ..< 30 { expected.append(hand.line(after: expected.last, places: 60, using: &random)) }
            #expect(grid.nextRows(30, columns: 60) == expected)
        }
    }

    /// `Flow` shows the counts growing as each line is scanned, so a picture
    /// learned a row at a time must hold, after every row, exactly the counts
    /// the hand-written chain holds for the rows so far.
    @Test func learningARowAtATimeKeepsTheSameCountsAsItGoes() throws {
        let picture = Self.picture(side: 40, values: 2, seed: 21)
        var grid = MarkovGrid<Int>(vocabulary: [0, 1], seed: 1)
        for (index, row) in picture.enumerated() {
            try grid.learn(row, after: index > 0 ? picture[index - 1] : nil)
            var hand = HandChain(values: 2)
            hand.learn(Array(picture[...index]))
            for arrangement in 0 ..< 16 {
                let cells = (0 ..< 4).map { (arrangement >> $0) & 1 }
                let tally = hand.counts[cells] ?? [0, 0]
                #expect(grid.count(of: 0, around: cells) == tally[0], "row \(index), arrangement \(cells)")
                #expect(grid.count(of: 1, around: cells) == tally[1], "row \(index), arrangement \(cells)")
            }
        }
        var whole = MarkovGrid<Int>(vocabulary: [0, 1], seed: 1)
        try whole.learn(picture)
        #expect(grid.nextRows(50, columns: 40) == whole.nextRows(50, columns: 40))
    }

    // MARK: - What a seed writes

    /// The grid a seed writes is pinned, so a change to the generator, to the
    /// order the cells around a place are read in, or to the way a value is
    /// chosen cannot quietly move a field someone tuned.
    @Test func aSeededGridIsPinned() throws {
        let picture = [
            "..##....",
            "..##..##",
            "......##",
            "##......",
            "##..##..",
            "....##..",
        ].map(Array.init)
        var grid = try MarkovGrid(learning: picture, seed: 11)
        let written = grid.nextRows(8, columns: 20).map { String($0) }
        #expect(written == Self.pinned)
    }

    private static let pinned: [String] = [
        "..#.......#####..##.",
        "..#..###..#####..##.",
        "###..###..#####..##.",
        ".....###..#####..##.",
        "..........#####.....",
        ".###.##.#######...##",
        ".###................",
        ".....###.#..###..###",
    ]

    @Test func theSameSeedWritesTheSameGridAndAnotherDoesNot() throws {
        let picture = Self.picture(side: 40, values: 5, seed: 31)
        var one = try MarkovGrid(learning: picture, seed: 11)
        var same = try MarkovGrid(learning: picture, seed: 11)
        var other = try MarkovGrid(learning: picture, seed: 12)

        let field = one.nextRows(60, columns: 80)
        #expect(field.count == 60)
        #expect(field.allSatisfy { $0.count == 80 })
        #expect(field == same.nextRows(60, columns: 80))
        #expect(field != other.nextRows(60, columns: 80))

        // Going back to the top rewinds the randomness as well as the place.
        one.reset()
        #expect(one.nextRows(60, columns: 80) == field)
    }

    /// A strip asked for a row at a time is the grid asked for whole.
    @Test func rowByRowIsTheWholeGrid() throws {
        let picture = Self.picture(side: 40, values: 5, seed: 32)
        var whole = try MarkovGrid(learning: picture, seed: 5)
        var strip = try MarkovGrid(learning: picture, seed: 5)
        let field = whole.nextRows(200, columns: 48)
        var rows: [[Int]] = []
        for _ in 0 ..< 200 { rows.append(strip.nextRow(columns: 48)) }
        #expect(rows == field)
        // And it goes on from where it is: more rows continue the strip.
        let more = whole.nextRows(3, columns: 48)
        #expect(more.count == 3)
        #expect(more == (0 ..< 3).map { _ in strip.nextRow(columns: 48) })
    }

    /// A roll walks the values in vocabulary order. Declared up front, that
    /// order is fixed, so the same pictures write the same grid whichever was
    /// shown first; left to the order of first sight, it is not.
    @Test func aDeclaredVocabularyMakesTheOrderOfShowingIrrelevant() throws {
        let a = Self.picture(side: 40, values: 5, seed: 41).map { $0.map { 4 - $0 } }
        let b = Self.picture(side: 40, values: 5, seed: 42)

        var ab = MarkovGrid<Int>(vocabulary: [0, 1, 2, 3, 4], seed: 9)
        try ab.learn(a); try ab.learn(b)
        var ba = MarkovGrid<Int>(vocabulary: [0, 1, 2, 3, 4], seed: 9)
        try ba.learn(b); try ba.learn(a)
        #expect(ab.vocabulary == [0, 1, 2, 3, 4])
        #expect(ab.nextRows(40, columns: 60) == ba.nextRows(40, columns: 60))

        var seenAB = MarkovGrid<Int>(seed: 9)
        try seenAB.learn(a); try seenAB.learn(b)
        var seenBA = MarkovGrid<Int>(seed: 9)
        try seenBA.learn(b); try seenBA.learn(a)
        #expect(seenAB.vocabulary != seenBA.vocabulary)
        #expect(seenAB.vocabulary.first == a[0][0])
        #expect(seenAB.nextRows(40, columns: 60) != seenBA.nextRows(40, columns: 60))
    }

    // MARK: - What it learned

    /// A picture with one way through is written back exactly, at any size.
    /// A checkerboard needs the cell above as well as the cell before, so the
    /// same picture at two orders is a counterfactual pair.
    @Test func aLongerReachResolvesWhatAShortOneCannot() throws {
        let board = (0 ..< 8).map { row in (0 ..< 8).map { ($0 + row) % 2 == 0 ? "a" : "b" } }

        var both = try MarkovGrid(learning: board, order: 2, seed: 3)
        let written = both.nextRows(30, columns: 41)
        for (r, row) in written.enumerated() {
            for (c, cell) in row.enumerated() {
                #expect(cell == ((r + c) % 2 == 0 ? "a" : "b"), "row \(r), column \(c)")
            }
        }

        // Along the row alone, a row alternates but cannot tell which way the
        // row above began: its first cell is a or b by the counts.
        var along = try MarkovGrid(learning: board, order: 1, seed: 3)
        let loose = along.nextRows(200, columns: 9)
        #expect(loose.allSatisfy { row in zip(row, row.dropFirst()).allSatisfy { $0 != $1 } })
        #expect(Set(loose.map { $0[0] }) == ["a", "b"])
        #expect(zip(loose, loose.dropFirst()).contains { $0[0] == $1[0] })
    }

    /// `order` is held to the four cells there are.
    @Test func orderIsHeldBetweenOneAndFour() {
        #expect(MarkovGrid<Int>(order: 0).order == 1)
        #expect(MarkovGrid<Int>(order: -3).order == 1)
        #expect(MarkovGrid<Int>(order: 9).order == 4)
        #expect(MarkovGrid<Int>().order == 4)
    }

    /// A place off the grid is a value of its own, and it is the nearest cell
    /// a first cell has, so it is never forgotten: what the pictures hold only
    /// in their first column is written in the first column and nowhere else.
    @Test func theLeftEdgeBehavesAsThePicturesLeftEdgeDid() throws {
        var random = SplitMix64(seed: 5)
        let picture: [[Character]] = (0 ..< 30).map { _ in
            ["|"] + (0 ..< 20).map { _ in random.next() % 3 == 0 ? "x" : "." }
        }
        for order in 1 ... 4 {
            var grid = try MarkovGrid(learning: picture, order: order, seed: 2)
            for row in grid.nextRows(80, columns: 70) {
                #expect(row[0] == "|")
                #expect(!row.dropFirst().contains("|"))
            }
        }
    }

    /// The transitions read off what was written match the counts that were
    /// learned, within sampling error. Every written cell is filed under the
    /// arrangement the hand-written chain would have kept for it, the tallies
    /// of five grids are pooled (one grid a seed, so no two share a row), and
    /// a chi-square is taken against the learned shares.
    @Test func whatIsWrittenFollowsTheLearnedCounts() throws {
        var hand = HandChain(values: 5)
        var grid = MarkovGrid<Int>(vocabulary: [0, 1, 2, 3, 4])
        for picture in Self.pictures(values: 5) {
            hand.learn(picture)
            try grid.learn(picture)
        }

        var observed: [[Int]: [Int]] = [:]
        for seed in 1 ... 5 {
            var writer = MarkovGrid<Int>(vocabulary: [0, 1, 2, 3, 4], seed: seed)
            for picture in Self.pictures(values: 5) { try writer.learn(picture) }
            let rows = writer.nextRows(150, columns: 150)
            for (r, row) in rows.enumerated() {
                for (p, value) in row.enumerated() {
                    let kept = hand.kept(hand.around(p, in: row, after: r > 0 ? rows[r - 1] : nil))
                    observed[kept, default: [0, 0, 0, 0, 0]][value] += 1
                }
            }
        }

        var statistic = 0.0
        var freedom = 0
        var cells = 0
        for (arrangement, seen) in observed {
            let learned = try #require(hand.counts[arrangement])
            let total = Double(seen.reduce(0, +)), learnedTotal = Double(learned.reduce(0, +))
            // Nothing may be written that the counts give no chance to.
            for value in 0 ..< 5 where learned[value] == 0 { #expect(seen[value] == 0, "\(arrangement) wrote \(value)") }

            // Values expected fewer than five times are pooled into one bin.
            var bins: [(seen: Double, expected: Double)] = []
            var rest = (seen: 0.0, expected: 0.0)
            for value in 0 ..< 5 where learned[value] > 0 {
                let expected = total * Double(learned[value]) / learnedTotal
                if expected >= 5 {
                    bins.append((Double(seen[value]), expected))
                } else {
                    rest.seen += Double(seen[value])
                    rest.expected += expected
                }
            }
            if rest.expected >= 5 { bins.append(rest) }
            guard bins.count >= 2 else { continue }
            // With the leftover dropped the bins no longer sum to the total,
            // so each stands free; with nothing dropped one is given.
            let dropped = rest.expected > 0 && rest.expected < 5
            for bin in bins { statistic += (bin.seen - bin.expected) * (bin.seen - bin.expected) / bin.expected }
            freedom += dropped ? bins.count : bins.count - 1
            cells += Int(total)
        }

        #expect(cells > 50_000)
        #expect(freedom >= 30)
        // The Wilson-Hilferty normal form of a chi-square: z is its distance
        // from what chance gives, in standard deviations.
        let k = Double(freedom)
        let z = (pow(statistic / k, 1.0 / 3.0) - (1 - 2 / (9 * k))) / (2 / (9 * k)).squareRoot()
        #expect(abs(z) < 3, "chi-square \(statistic) on \(freedom) degrees of freedom, z \(z)")
    }

    /// The counts are readable, which is what lets a sketch draw the table.
    @Test func whatItLearnedCanBeReadBack() throws {
        let picture = [
            ["x", "y", "y"],
            ["x", "y", "x"],
            ["x", "x", "y"],
        ]
        let grid = try MarkovGrid(learning: picture, seed: 1)
        #expect(grid.vocabulary == ["x", "y"])

        // With no cells: how often each value appeared at all.
        #expect(grid.count(of: "x", around: []) == 5)
        #expect(grid.count(of: "y", around: []) == 4)
        // After an x in its row: y, y, x, y.
        #expect(grid.count(of: "y", around: ["x"]) == 3)
        #expect(grid.count(of: "x", around: ["x"]) == 1)
        // A first cell has the edge before it, and every one is an x.
        #expect(grid.count(of: "x", around: [nil]) == 3)
        #expect(grid.count(of: "y", around: [nil]) == 0)
        // The whole arrangement of the middle cell: x before, y above, x above
        // and before, y above and after.
        #expect(grid.count(of: "y", around: ["x", "y", "x", "y"]) == 1)
        // Nothing is forgotten when counting: an arrangement never shown is 0.
        #expect(grid.count(of: "y", around: ["y", "y", "y", "y"]) == 0)
        #expect(grid.count(of: "z", around: []) == 0)

        let after = grid.continuations(around: ["x"])
        #expect(after.map(\.element) == ["y", "x"])
        #expect(abs(after[0].probability - 0.75) < 1e-12)
        #expect(abs(after.reduce(0) { $0 + $1.probability } - 1) < 1e-12)
        // Reading what may come does forget, as writing does. The picture has
        // a y before, above, and above and before one cell, an x, and nothing
        // above and after it, so the fourth y is the cell that is forgotten.
        #expect(grid.count(of: "x", around: ["y", "y", "y", "y"]) == 0)
        let kept = grid.continuations(around: ["y", "y", "y", "y"])
        #expect(kept.map(\.element) == ["x"])
        #expect(kept.map(\.element) == grid.continuations(around: ["y", "y", "y"]).map(\.element))
        // A value it never saw matches nothing, so all that is left is the
        // shares: five x to four y.
        #expect(grid.continuations(around: ["z"]).map(\.element) == ["x", "y"])
        #expect(MarkovGrid<String>().continuations(around: []).isEmpty)
    }

    /// Ties come back in vocabulary order, never in a table's own order.
    @Test func tiedContinuationsKeepVocabularyOrder() {
        var grid = MarkovGrid<String>(vocabulary: ["c", "a", "b"], seed: 1)
        for value in ["b", "a", "c"] { grid.learn(value, around: ["a"], times: 2) }
        #expect(grid.continuations(around: ["a"]).map(\.element) == ["c", "a", "b"])
    }

    // MARK: - Declared counts

    /// A table of counts and the picture it was counted from are one grid:
    /// every cell declared under the cells a picture would have given it
    /// writes the same rows.
    @Test func declaredCountsWriteLikeThePictureTheyWereCountedFrom() throws {
        let picture = Self.picture(side: 24, values: 5, seed: 51)
        var learned = try MarkovGrid(learning: picture, seed: 7)

        var declared = MarkovGrid<Int>(seed: 7)
        for (r, row) in picture.enumerated() {
            for (p, value) in row.enumerated() {
                func cell(_ r: Int, _ p: Int) -> Int? {
                    picture.indices.contains(r) && row.indices.contains(p) ? picture[r][p] : nil
                }
                declared.learn(value, around: [cell(r, p - 1), cell(r - 1, p), cell(r - 1, p - 1), cell(r - 1, p + 1)])
            }
        }
        #expect(declared.vocabulary == learned.vocabulary)
        #expect(declared.nextRows(60, columns: 50) == learned.nextRows(60, columns: 50))
    }

    /// `times` is the count: one call with 3 is three calls with 1, a count
    /// below 1 records nothing, and cells past `order` are not read.
    @Test func timesCountsAsThatManyCells() {
        var once = MarkovGrid<String>(order: 2, seed: 1)
        once.learn("b", around: ["a", nil], times: 3)
        once.learn("c", around: ["a", nil])
        once.learn("d", around: ["a", nil], times: 0)
        once.learn("d", around: ["a", nil], times: -4)
        #expect(once.vocabulary == ["b", "a", "c"])
        #expect(once.count(of: "b", around: ["a", nil]) == 3)
        #expect(once.count(of: "b", around: ["a"]) == 3)
        #expect(once.count(of: "b", around: []) == 3)
        #expect(once.count(of: "c", around: ["a", nil]) == 1)

        var deep = MarkovGrid<String>(order: 2, seed: 1)
        deep.learn("b", around: ["a", nil, "q", "q"], times: 3)
        #expect(deep.count(of: "b", around: ["a", nil, "z", "z"]) == 3)
        #expect(deep.vocabulary == ["b", "a"])
    }

    // MARK: - Never without an answer

    @Test func anUnseenArrangementForgetsRatherThanStopping() throws {
        var grid = try MarkovGrid(learning: [[1, 2], [3, 1]], seed: 5)
        // A row of values it never saw, wider than anything it was shown.
        grid.start(after: Array(repeating: 99, count: 40))
        let rows = grid.nextRows(50, columns: 40)
        #expect(rows.count == 50)
        #expect(rows.allSatisfy { $0.count == 40 && $0.allSatisfy([1, 2, 3].contains) })

        // A value it never saw is not the edge. Under a row of strangers a
        // first cell is drawn from every first cell the picture has, where
        // under the edge it would be the top row's first cell every time.
        let board = (0 ..< 8).map { row in (0 ..< 8).map { ($0 + row) % 2 } }
        var firsts = Set<Int>()
        for seed in 0 ..< 40 {
            var under = try MarkovGrid(learning: board, order: 2, seed: seed)
            #expect(under.nextRow(columns: 4)[0] == 0)
            under.start(after: [9, 9, 9, 9])
            firsts.insert(under.nextRow(columns: 4)[0])
        }
        #expect(firsts == [0, 1])

        // A width that changes between rows reads the missing places as off
        // the grid.
        #expect(grid.nextRow(columns: 3).count == 3)
        #expect(grid.nextRow(columns: 90).count == 90)
    }

    @Test func aGridShownNothingWritesNothing() {
        var empty = MarkovGrid<Int>(vocabulary: [1, 2, 3], seed: 1)
        #expect(empty.isEmpty)
        #expect(empty.nextRow(columns: 8).isEmpty)
        #expect(empty.nextRows(4, columns: 8).isEmpty)

        var shown = MarkovGrid<Int>(seed: 1)
        shown.learn(7, around: [])
        #expect(!shown.isEmpty)
        #expect(shown.nextRow(columns: 0).isEmpty)
        #expect(shown.nextRow(columns: -5).isEmpty)
        #expect(shown.nextRows(-2, columns: 4).isEmpty)
        #expect(shown.nextRows(3, columns: 0).isEmpty)
        #expect(shown.nextRows(2, columns: 3) == [[7, 7, 7], [7, 7, 7]])
    }

    /// Starting under a row of your own grows what is written out of it.
    @Test func startingAfterARowCarriesOnFromIt() throws {
        let board = (0 ..< 8).map { row in (0 ..< 8).map { ($0 + row) % 2 } }
        var grid = try MarkovGrid(learning: board, order: 2, seed: 3)
        #expect(grid.nextRow(columns: 6) == [0, 1, 0, 1, 0, 1])
        grid.start(after: [0, 1, 0, 1, 0, 1])
        #expect(grid.nextRow(columns: 6) == [1, 0, 1, 0, 1, 0])
        grid.start(after: [1, 0, 1, 0, 1, 0])
        #expect(grid.nextRow(columns: 6) == [0, 1, 0, 1, 0, 1])
        // Back at the top, the row above is off the grid again.
        grid.start(after: [1, 0, 1, 0, 1, 0])
        grid.reset()
        #expect(grid.nextRow(columns: 6) == [0, 1, 0, 1, 0, 1])
    }

    // MARK: - A picture that cannot be read

    @Test func anEmptyOrRaggedPictureThrowsAndTeachesNothing() throws {
        var grid = MarkovGrid<Int>(seed: 1)
        #expect(throws: MarkovGridError.empty) { try grid.learn([]) }
        #expect(throws: MarkovGridError.empty) { try grid.learn([[]]) }
        #expect(throws: MarkovGridError.empty) { try grid.learn([[], [1]]) }
        #expect(throws: MarkovGridError.ragged(row: 2, count: 3, expected: 4)) {
            try grid.learn([[1, 2, 3, 4], [1, 2, 3, 4], [1, 2, 3], [1, 2, 3, 4]])
        }
        #expect(throws: MarkovGridError.ragged(row: 1, count: 5, expected: 4)) {
            try grid.learn([[1, 2, 3, 4], [1, 2, 3, 4, 5]])
        }
        #expect(throws: MarkovGridError.empty) { try grid.learn([], after: [1, 2]) }
        #expect(throws: MarkovGridError.ragged(row: 1, count: 2, expected: 3)) {
            try grid.learn([1, 2], after: [1, 2, 3])
        }
        #expect(throws: MarkovGridError.empty) { _ = try MarkovGrid<Int>(learning: []) }
        // A picture refused is not half learned.
        #expect(grid.isEmpty)
        #expect(grid.vocabulary.isEmpty)
        #expect(grid.nextRow(columns: 4).isEmpty)

        #expect(MarkovGridError.empty.description == "The picture has no cells to learn from.")
        #expect(MarkovGridError.ragged(row: 2, count: 3, expected: 4).description
            == "Row 3 of the picture has 3 cells where the rows before it have 4.")
    }

    /// Pictures of different sizes are learned side by side.
    @Test func picturesNeedNotBeOneSize() throws {
        var grid = MarkovGrid<Character>(seed: 4)
        try grid.learn(["ab", "ba"].map(Array.init))
        try grid.learn(["abab", "baba", "abab"].map(Array.init))
        #expect(grid.count(of: "a", around: []) == 8)
        #expect(grid.nextRows(5, columns: 7).count == 5)
    }
}
