import Foundation
import Ollin
import Testing

/// Hitomezashi invariants: the dash alternation on every line, the bit as a
/// phase, bit repetition, the two-coloring theorem (parity flips exactly across
/// a stitch), and seeded reproducibility.
@Suite struct HitomezashiTests {
    private let frame = Rectangle(x: 0, y: 0, width: 240, height: 240)

    /// On any single line, dashes cover alternating cells: sorted along the
    /// line, consecutive dashes always leave exactly one cell of gap.
    @Test func dashesAlternateOnEveryLine() {
        var rng = SplitMix64(seed: 9)
        let design = Hitomezashi(grid: Grid(in: frame, columns: 8, rows: 6), using: &rng)
        let cellW = frame.width / 8

        for line in 0...6 {
            let y = frame.y + frame.height * Double(line) / 6
            let starts = design.stitches
                .filter { abs($0.points[0].y - y) < 1e-9 && abs($0.points[1].y - y) < 1e-9 }
                .map { min($0.points[0].x, $0.points[1].x) }
                .sorted()
            for (a, b) in zip(starts, starts.dropFirst()) {
                #expect(abs((b - a) - 2 * cellW) < 1e-9,
                        "dashes on one line must skip exactly one cell")
            }
        }
    }

    /// The line's bit is a phase: `false` starts the dashes on the edge,
    /// `true` starts them one cell in.
    @Test func bitShiftsThePhase() {
        let grid = Grid(in: frame, columns: 4, rows: 4)
        let onEdge = Hitomezashi(grid: grid, rowBits: [false], columnBits: [])
        let shifted = Hitomezashi(grid: grid, rowBits: [true], columnBits: [])

        func topLineStarts(_ d: Hitomezashi) -> [Double] {
            d.stitches
                .filter { abs($0.points[0].y - frame.y) < 1e-9 && abs($0.points[1].y - frame.y) < 1e-9 }
                .map { min($0.points[0].x, $0.points[1].x) }
                .sorted()
        }
        let cellW = frame.width / 4
        #expect(topLineStarts(onEdge) == [frame.x, frame.x + 2 * cellW])
        #expect(topLineStarts(shifted) == [frame.x + cellW, frame.x + 3 * cellW])
    }

    /// Shorter bit arrays repeat along their lines, so a one-bit motif equals
    /// the fully spelled-out design.
    @Test func shortBitArraysRepeat() {
        let grid = Grid(in: frame, columns: 6, rows: 6)
        let motif = Hitomezashi(grid: grid, rowBits: [true, false], columnBits: [false])
        let spelled = Hitomezashi(grid: grid,
                                  rowBits: [true, false, true, false, true, false, true],
                                  columnBits: [Bool](repeating: false, count: 7))
        #expect(motif.stitches == spelled.stitches)
        #expect(motif.parities == spelled.parities)
    }

    /// The two-coloring theorem: two side-by-side cells get different parities
    /// exactly when a stitch lies on their shared edge. Checked geometrically
    /// against the emitted stitches, so it also pins that the two faces agree.
    @Test func parityFlipsExactlyAcrossAStitch() {
        var rng = SplitMix64(seed: 41)
        let columns = 7, rows = 5
        let design = Hitomezashi(grid: Grid(in: frame, columns: columns, rows: rows),
                                 probability: 0.5, using: &rng)
        let parities = design.parities
        let cellW = frame.width / Double(columns)
        let cellH = frame.height / Double(rows)

        func hasStitch(from a: Vector2, to b: Vector2) -> Bool {
            design.stitches.contains { dash in
                (dash.points[0].distance(to: a) < 1e-9 && dash.points[1].distance(to: b) < 1e-9)
                    || (dash.points[0].distance(to: b) < 1e-9 && dash.points[1].distance(to: a) < 1e-9)
            }
        }

        for row in 0..<rows {
            for column in 1..<columns {
                let x = frame.x + Double(column) * cellW
                let top = Vector2(x, frame.y + Double(row) * cellH)
                let separated = hasStitch(from: top, to: Vector2(x, top.y + cellH))
                let differ = parities[row * columns + column] != parities[row * columns + column - 1]
                #expect(differ == separated)
            }
        }
        for row in 1..<rows {
            for column in 0..<columns {
                let y = frame.y + Double(row) * cellH
                let left = Vector2(frame.x + Double(column) * cellW, y)
                let separated = hasStitch(from: left, to: Vector2(left.x + cellW, y))
                let differ = parities[row * columns + column] != parities[(row - 1) * columns + column]
                #expect(differ == separated)
            }
        }
    }

    /// The seeded form is a pure function of the seed, and a biased probability
    /// still emits a full design (every line keeps its dashes; only the phase
    /// varies).
    @Test func seededDesignsReproduce() {
        let grid = Grid(in: frame, columns: 10, rows: 10)
        var a = SplitMix64(seed: 7), b = SplitMix64(seed: 7)
        #expect(Hitomezashi(grid: grid, using: &a) == Hitomezashi(grid: grid, using: &b))

        var c = SplitMix64(seed: 7)
        let biased = Hitomezashi(grid: grid, probability: 0, using: &c)
        #expect(biased.rowBits.allSatisfy { !$0 })
        // 11 lines each way, 5 dashes per line at phase false.
        #expect(biased.stitches.count == 11 * 5 * 2)
    }

    /// Degenerate grids emit nothing rather than trapping.
    @Test func emptyGridsAreEmpty() {
        let flat = Hitomezashi(grid: Grid(in: frame, columns: 0, rows: 5),
                               rowBits: [true], columnBits: [false])
        #expect(flat.stitches.isEmpty)
        #expect(flat.parities.isEmpty)
    }
}
