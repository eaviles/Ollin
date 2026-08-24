import Ollin
import Testing

/// Laws for the maze of diagonals. Joining the diagonals into runs must not lose,
/// duplicate, or invent a single one, every step of a run is a cell's diagonal,
/// and a field of one diagonal joins into exactly the anti-diagonals of the grid.
@Suite
struct TenPrintTests {
    private let bounds = Rectangle(x: 0, y: 0, width: 120, height: 120)

    private func maze(_ columns: Int, _ rows: Int, bits: [Bool]) -> TenPrint {
        TenPrint(grid: Grid(in: bounds, columns: columns, rows: rows), bits: bits)
    }

    private func mixed(_ columns: Int, _ rows: Int, seed: UInt64 = 7) -> TenPrint {
        var rng = SplitMix64(seed: seed)
        return TenPrint(grid: Grid(in: bounds, columns: columns, rows: rows), using: &rng)
    }

    // MARK: - One diagonal per cell

    /// One line per cell, and each one runs corner to corner of its own cell.
    @Test func everyCellDrawsOneDiagonal() {
        let design = mixed(6, 6)
        #expect(design.lines.count == 36)
        let diagonal = Vector2(20, 20).length          // a 20x20 cell
        for line in design.lines {
            #expect(line.points.count == 2)
            #expect(!line.isClosed)
            #expect(abs((line.points[1] - line.points[0]).length - diagonal) < 1e-9)
        }
    }

    /// The bit chooses which way the diagonal leans, and nothing else.
    @Test func theBitChoosesTheLean() {
        let back = maze(1, 1, bits: [true]).lines[0].points
        let forward = maze(1, 1, bits: [false]).lines[0].points
        // The back diagonal falls to the right as it goes down; the forward one rises.
        #expect((back[1].x - back[0].x) * (back[1].y - back[0].y) > 0)
        #expect((forward[1].x - forward[0].x) * (forward[1].y - forward[0].y) < 0)
    }

    /// A short bit list repeats, so a small motif tiles a large field.
    @Test func aShortBitListRepeats() {
        let design = maze(4, 4, bits: [true, false])
        for row in 0 ..< 4 {
            for column in 0 ..< 4 {
                #expect(design.bit(column: column, row: row) == ((row * 4 + column) % 2 == 0))
            }
        }
    }

    // MARK: - Joining them up

    /// Joining loses nothing and invents nothing: the runs walk over exactly the
    /// diagonals the cells drew, each one once.
    @Test func theRunsCoverEveryDiagonalExactlyOnce() {
        let design = mixed(9, 9)
        var drawn: [String: Int] = [:]
        for line in design.lines { drawn[key(line.points[0], line.points[1]), default: 0] += 1 }

        var walked: [String: Int] = [:]
        for run in design.runs {
            for i in 1 ..< run.points.count {
                walked[key(run.points[i - 1], run.points[i]), default: 0] += 1
            }
        }
        #expect(walked == drawn)
    }

    /// The same thing measured rather than counted: the ink is conserved.
    @Test func theRunsCarryTheSameLength() {
        let design = mixed(11, 11, seed: 3)
        let separate = design.lines.reduce(0.0) { $0 + $1.length }
        let joined = design.runs.reduce(0.0) { $0 + $1.length }
        #expect(abs(joined - separate) < 1e-6)
    }

    /// Every step of a run is one cell's diagonal, never a jump across the field.
    @Test func aRunOnlyEverStepsOneDiagonal() {
        let design = mixed(10, 10, seed: 11)
        let diagonal = Vector2(12, 12).length
        for run in design.runs {
            #expect(run.points.count >= 2)
            #expect(!run.isClosed)
            for i in 1 ..< run.points.count {
                #expect(abs((run.points[i] - run.points[i - 1]).length - diagonal) < 1e-9)
            }
        }
    }

    /// A field of one diagonal joins into exactly the anti-diagonals of the grid:
    /// five of them on a three by three, of one, two, three, two and one segments.
    /// Nothing about the walk is free to choose here, so the count is exact.
    @Test func oneLeanEverywhereJoinsIntoTheAntiDiagonals() {
        let design = maze(3, 3, bits: [false])
        let runs = design.runs
        #expect(runs.count == 5)
        #expect(runs.map { $0.points.count - 1 }.sorted() == [1, 1, 2, 2, 3])
    }

    /// A chain with two loose ends comes back as one run, not two. Three cells in
    /// a row leaning down, up, down join end to end into a single zigzag whose
    /// only odd corners are its two ends. A walk that starts in the middle of it
    /// leaves through one end and has to come back for the other half, so this is
    /// the law that the start-where-a-path-must-end rule is for: without it every
    /// other law here still passes and this one does not.
    @Test func aChainWithTwoLooseEndsComesBackAsOneRun() {
        let design = maze(3, 1, bits: [false, true, false])
        let runs = design.runs
        #expect(runs.count == 1)
        #expect(runs.first?.points.count == 4)
    }

    /// A path has to end wherever an odd number of diagonals meet, so there can
    /// never be fewer runs than half those corners.
    @Test func thereAreNeverFewerRunsThanTheCornersDemand() {
        for seed in UInt64(1) ... 6 {
            let design = mixed(8, 8, seed: seed)
            var degree: [String: Int] = [:]
            for line in design.lines {
                degree[point(line.points[0]), default: 0] += 1
                degree[point(line.points[1]), default: 0] += 1
            }
            let odd = degree.values.filter { $0 % 2 == 1 }.count
            #expect(design.runs.count >= odd / 2, "seed \(seed)")
        }
    }

    /// An empty grid draws nothing rather than trapping the walk.
    @Test func anEmptyGridDrawsNothing() {
        let design = maze(0, 0, bits: [])
        #expect(design.lines.isEmpty)
        #expect(design.runs.isEmpty)
    }

    // MARK: - Keys

    private func point(_ v: Vector2) -> String {
        "\(Int((v.x * 1000).rounded())),\(Int((v.y * 1000).rounded()))"
    }

    /// A segment named by its two ends, in a fixed order, so a run walked either
    /// way matches the line it came from.
    private func key(_ a: Vector2, _ b: Vector2) -> String {
        let one = point(a), two = point(b)
        return one < two ? "\(one)|\(two)" : "\(two)|\(one)"
    }
}
