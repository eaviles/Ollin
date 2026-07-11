import Ollin
import Testing

/// Pure-CPU checks on the 1D cellular automata: known rule tables produce their
/// published rows, the totalistic code digits decode right, and edges wrap (or not)
/// as asked.
@Suite
struct ElementaryCATests {

    /// Reads a row as a compact string, "1" for live, centered on `width`.
    private func line(_ row: [Bool]) -> String {
        row.map { $0 ? "1" : "0" }.joined()
    }

    /// Rule 30's first four generations from a single center seed, the classic
    /// hand-checkable triangle: 1 / 111 / 11001 / 1101111.
    @Test func rule30KnownRows() {
        let rows = elementaryCA(rule: 30, width: 9, generations: 4)
        #expect(line(rows[0]) == "000010000")
        #expect(line(rows[1]) == "000111000")
        #expect(line(rows[2]) == "001100100")
        #expect(line(rows[3]) == "011011110")
    }

    /// Rule 110 grows leftward with its published signature: 11 / 111 / 1101.
    @Test func rule110KnownRows() {
        let rows = elementaryCA(rule: 110, width: 9, generations: 4)
        #expect(line(rows[1]) == "000110000")
        #expect(line(rows[2]) == "001110000")
        #expect(line(rows[3]) == "011010000")
    }

    /// Rule 90 is the Sierpinski triangle: cell at center offset p of generation n is
    /// live exactly when C(n, (n+p)/2) is odd (Lucas: the chosen index is a submask).
    @Test func rule90IsSierpinski() {
        let width = 65, center = 32
        let rows = elementaryCA(rule: 90, width: width, generations: 33)
        for n in 0 ..< 33 {
            for i in 0 ..< width {
                let p = i - center
                let expected: Bool
                if abs(p) > n || (n + p) % 2 != 0 {
                    expected = false
                } else {
                    let k = (n + p) / 2
                    expected = (n & k) == k   // binomial parity
                }
                #expect(rows[n][i] == expected, "generation \(n), cell \(i)")
            }
        }
    }

    /// The ends only see each other when `wrap` is on: a seed at index 0 under the
    /// grow-everywhere rule 254 reaches the far end in one step only on the ring.
    @Test func wrapControlsTheEdges() {
        let start: [Bool] = [true, false, false, false, false]
        let ring = elementaryCA(rule: 254, width: 5, generations: 2, from: start, wrap: true)
        let strip = elementaryCA(rule: 254, width: 5, generations: 2, from: start, wrap: false)
        #expect(line(ring[1]) == "11001")
        #expect(line(strip[1]) == "11000")
    }

    /// A start row is padded or trimmed to `width`, and the row count is exact.
    @Test func startRowNormalizes() {
        let padded = elementaryCA(rule: 30, width: 6, generations: 3, from: [true])
        #expect(padded[0] == [true, false, false, false, false, false])
        #expect(padded.count == 3)
        let trimmed = elementaryCA(rule: 30, width: 2, generations: 1,
                                   from: [false, true, true, true])
        #expect(trimmed[0] == [false, true])
    }

    /// Totalistic code 777 over 3 colors: digits decode LSB-first (0,1,2,1,0,0,1), so
    /// a single seed grows 111 then 1 2 1 2 1, the hand-checkable opening.
    @Test func totalistic777KnownRows() {
        let rows = totalisticCA(code: 777, colors: 3, width: 9, generations: 3)
        #expect(rows[0] == [0, 0, 0, 0, 1, 0, 0, 0, 0])
        #expect(rows[1] == [0, 0, 0, 1, 1, 1, 0, 0, 0])
        #expect(rows[2] == [0, 0, 1, 2, 1, 2, 1, 0, 0])
    }

    /// A two-color totalistic code reduces to sums: code 14 (live on any neighbor sum
    /// of 1...3) grows a solid triangle, one cell per side per generation.
    @Test func totalisticSolidTriangle() {
        let rows = totalisticCA(code: 14, colors: 2, width: 11, generations: 5)
        for (n, row) in rows.enumerated() {
            let live = row.enumerated().filter { $0.element > 0 }.map(\.offset)
            #expect(live.first == 5 - n && live.last == 5 + n, "generation \(n)")
            #expect(live.count == 2 * n + 1, "generation \(n)")
        }
    }
}

/// Behavioral pins on the turmite machine: Langton's ant flips exactly one cell per
/// step and settles into its 104-step highway, movement semantics hold on a simple
/// rule, and a fixed setup reproduces.
@Suite
struct TurmiteTests {

    /// Langton's ant always writes the opposite color, so the painted-cell count has
    /// the parity of the step count, and never exceeds it.
    @Test func langtonPopulationParity() {
        let ant = Turmite(.langton, columns: 128, rows: 128)
        for steps in [1, 10, 105, 500] {
            ant.step(steps)
            let population = ant.paintedCells.count
            #expect(population % 2 == ant.stepCount % 2)
            #expect(population <= ant.stepCount)
        }
    }

    /// After ~10,000 chaotic steps Langton's ant builds the highway: displacement over
    /// each 104-step period is the same diagonal (|dx| = |dy| = 2).
    @Test func langtonHighwayPeriod() {
        let ant = Turmite(.langton, columns: 512, rows: 512)
        ant.step(10500)
        let a = ant.antPositions[0]
        ant.step(104)
        let b = ant.antPositions[0]
        ant.step(104)
        let c = ant.antPositions[0]
        let delta1 = (b.column - a.column, b.row - a.row)
        let delta2 = (c.column - b.column, c.row - b.row)
        #expect(delta1 == delta2)
        #expect(abs(delta1.0) == 2 && abs(delta1.1) == 2)
    }

    /// A rule that always goes straight marches the ant up its column, wraps the grid,
    /// and returns home after exactly `rows` steps, painting the full column.
    @Test func straightRuleWrapsColumn() {
        let rule = [[Turmite.Rule(write: 1, turn: .straight, state: 0),
                     Turmite.Rule(write: 1, turn: .straight, state: 0)]]
        let machine = Turmite(rules: rule, columns: 9, rows: 9)
        let home = machine.antPositions[0]
        machine.step(9)
        #expect(machine.antPositions[0] == home)
        let painted = machine.paintedCells
        #expect(painted.count == 9)
        #expect(painted.allSatisfy { $0.column == home.column })
    }

    /// Same preset, same steps: identical painting and walker state (no hidden
    /// randomness, no iteration-order dependence).
    @Test func deterministicReplay() {
        let a = Turmite(.chaos, columns: 96, rows: 96)
        let b = Turmite(.chaos, columns: 96, rows: 96)
        a.step(5000)
        b.step(5000)
        #expect(a.antPositions[0] == b.antPositions[0])
        let cellsA = a.paintedCells, cellsB = b.paintedCells
        #expect(cellsA.count == cellsB.count)
        #expect(zip(cellsA, cellsB).allSatisfy { $0.0 == $0.1 })
    }

    /// Every preset is a well-formed 2-color table, and multiple ants step in order.
    @Test func presetsAreWellFormed() {
        for preset in Turmite.Preset.allCases {
            let machine = Turmite(preset, columns: 32, rows: 32,
                                  ants: [(8, 8), (24, 24)])
            #expect(machine.colors == 2)
            machine.step(100)
            #expect(machine.stepCount == 100)
            #expect(machine.antPositions.count == 2)
        }
    }
}
