import Ollin
import Testing

/// Pure-CPU checks on `Percolation`: the fill is seeded, the union-find labels
/// agree with 4-neighbor adjacency, clusters come largest first and partition
/// the open cells, spanning is read off the top and bottom rows, and the
/// outline tracer closes exact rectilinear loops with holes. No GPU.
@Suite
struct PercolationTests {

    /// Build a grid from strings, `#` open and `.` closed.
    private func staged(_ art: [String]) -> Percolation {
        let rows = art.count, columns = art[0].count
        var open: [Bool] = []
        for line in art { for ch in line { open.append(ch == "#") } }
        return Percolation(columns: columns, rows: rows, openCells: open)
    }

    @Test
    func theSameSeedFillsTheSameGrid() {
        var a = SplitMix64(seed: 21), b = SplitMix64(seed: 21)
        let first = Percolation(columns: 40, rows: 40, probability: 0.55, using: &a)
        let second = Percolation(columns: 40, rows: 40, probability: 0.55, using: &b)
        #expect(first == second)
    }

    @Test
    func theDegenerateProbabilitiesBehave() {
        var rng = SplitMix64(seed: 3)
        let closed = Percolation(columns: 12, rows: 12, probability: 0, using: &rng)
        #expect(closed.clusterCount == 0)
        #expect(!closed.spans)
        let full = Percolation(columns: 12, rows: 12, probability: 1, using: &rng)
        #expect(full.clusterCount == 1)
        #expect(full.clusterSizes == [144])
        #expect(full.spans)
    }

    @Test
    func adjacentOpenCellsAlwaysShareACluster() {
        var rng = SplitMix64(seed: 8)
        let p = Percolation(columns: 48, rows: 48, probability: 0.58, using: &rng)
        for row in 0 ..< 48 {
            for col in 0 ..< 48 where p.isOpen(column: col, row: row) {
                if p.isOpen(column: col + 1, row: row) {
                    #expect(p.clusterIndex(column: col, row: row)
                            == p.clusterIndex(column: col + 1, row: row))
                }
                if p.isOpen(column: col, row: row + 1) {
                    #expect(p.clusterIndex(column: col, row: row)
                            == p.clusterIndex(column: col, row: row + 1))
                }
            }
        }
    }

    @Test
    func clustersComeLargestFirstAndPartitionTheOpenCells() {
        var rng = SplitMix64(seed: 5)
        let p = Percolation(columns: 40, rows: 40, probability: 0.5, using: &rng)
        let sizes = p.clusterSizes
        for i in 1 ..< sizes.count { #expect(sizes[i - 1] >= sizes[i]) }
        #expect(sizes.reduce(0, +) == p.openCells.filter { $0 }.count)
    }

    @Test
    func diagonalContactDoesNotJoin() {
        let p = staged(["#.",
                        ".#"])
        #expect(p.clusterCount == 2)
    }

    @Test
    func aColumnSpansAndABrokenOneDoesNot() {
        let whole = staged([".#.",
                            ".#.",
                            ".#."])
        #expect(whole.spans)
        #expect(whole.spanningClusterIndex == 0)
        let broken = staged([".#.",
                             "...",
                             ".#."])
        #expect(!broken.spans)
    }

    @Test
    func aSingleCellOutlinesAsItsSquare() {
        let p = staged(["#"])
        let rect = Rectangle(x: 10, y: 20, width: 30, height: 40)
        let loops = p.outlines(of: 0, in: rect)
        #expect(loops.count == 1)
        #expect(loops[0].isClosed)
        #expect(loops[0].points.count == 4)
        #expect(loops[0].points.contains(Vector2(10, 20)))
        #expect(loops[0].points.contains(Vector2(40, 60)))
    }

    @Test
    func aDominoMergesItsCollinearEdges() {
        let p = staged(["##"])
        let loops = p.outlines(of: 0, in: Rectangle(x: 0, y: 0, width: 20, height: 10))
        #expect(loops.count == 1)
        #expect(loops[0].points.count == 4)
    }

    @Test
    func aRingClusterTracesAnOuterLoopAndAHole() {
        let p = staged(["###",
                        "#.#",
                        "###"])
        #expect(p.clusterCount == 1)
        let loops = p.outlines(of: 0, in: Rectangle(x: 0, y: 0, width: 30, height: 30))
        #expect(loops.count == 2)
        #expect(loops.allSatisfy { $0.points.count == 4 })
    }

    @Test
    func theThresholdSeparatesTheRegimes() {
        var sparse = SplitMix64(seed: 17)
        let below = Percolation(columns: 64, rows: 64, probability: 0.45, using: &sparse)
        #expect(!below.spans)
        var dense = SplitMix64(seed: 17)
        let above = Percolation(columns: 64, rows: 64, probability: 0.75, using: &dense)
        #expect(above.spans)
    }
}
