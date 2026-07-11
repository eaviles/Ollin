import Foundation

/// A **turmite**: a tiny Turing machine walking a color grid, painting as it goes.
/// Each step an ant reads the color under it, looks up its (state, color) rule, writes
/// that rule's color, turns, moves one cell forward (the grid wraps), and adopts the
/// rule's next state. Langton's ant is the 1-state, 2-color classic: chaos for ~10,000
/// steps, then an endless diagonal highway. Other rule tables spiral, weave textures,
/// or count in base phi; the `Preset` catalog collects known characters.
///
/// A stateful stepper you make once and hold (the `DifferentialGrowth` shape): call
/// `step(_:)` each frame, then read the painted cells back to draw them. Deterministic,
/// with no randomness anywhere, so a fixed step count always paints the same picture
/// and a fixed-frame snapshot reproduces.
///
/// ```swift
/// let ant = Turmite(.langton, columns: 270, rows: 270)
/// // in draw():
/// ant.step(250)
/// for cell in ant.paintedCells { /* fill a rect at (cell.column, cell.row) */ }
/// ```
public final class Turmite {

    /// Which way a rule turns the ant, relative to its heading.
    public enum Turn: Sendable {
        case straight
        case right
        case uTurn
        case left

        /// Quarter turns clockwise.
        fileprivate var quarters: Int {
            switch self {
            case .straight: return 0
            case .right:    return 1
            case .uTurn:    return 2
            case .left:     return 3
            }
        }
    }

    /// One instruction: what an ant in some state does on reading some color. It
    /// writes `write`, turns by `turn`, moves one cell forward, and enters `state`.
    public struct Rule: Sendable {
        public var write: Int
        public var turn: Turn
        public var state: Int

        public init(write: Int, turn: Turn, state: Int) {
            self.write = write
            self.turn = turn
            self.state = state
        }
    }

    /// Known turmites with distinct personalities. Each names its rule table; make one
    /// with `Turmite(.spiral, columns:rows:)` or read `rules` to tweak it.
    public enum Preset: String, CaseIterable, Sendable {
        /// The classic ant: chaos, then a diagonal highway after ~10,000 steps.
        case langton
        /// Spiral growth, a tightening square coil.
        case spiral
        /// Builds a highway after a period of chaotic growth.
        case highway
        /// Chaotic growth with a distinctive woven texture.
        case chaos
        /// Growth with a distinctive texture inside an expanding frame.
        case frame
        /// Counts its way outward in a Fibonacci-like spiral, growing very slowly.
        case fibonacci

        /// The preset's rule table, `[state][color]`.
        public var rules: [[Rule]] {
            switch self {
            case .langton:
                return [[Rule(write: 1, turn: .right, state: 0),
                         Rule(write: 0, turn: .left, state: 0)]]
            case .spiral:
                return [[Rule(write: 1, turn: .straight, state: 1),
                         Rule(write: 1, turn: .left, state: 0)],
                        [Rule(write: 1, turn: .right, state: 1),
                         Rule(write: 0, turn: .straight, state: 0)]]
            case .highway:
                return [[Rule(write: 1, turn: .right, state: 1),
                         Rule(write: 0, turn: .right, state: 1)],
                        [Rule(write: 1, turn: .straight, state: 0),
                         Rule(write: 1, turn: .straight, state: 1)]]
            case .chaos:
                return [[Rule(write: 1, turn: .right, state: 1),
                         Rule(write: 1, turn: .left, state: 1)],
                        [Rule(write: 1, turn: .right, state: 1),
                         Rule(write: 0, turn: .right, state: 0)]]
            case .frame:
                return [[Rule(write: 1, turn: .left, state: 0),
                         Rule(write: 1, turn: .right, state: 1)],
                        [Rule(write: 0, turn: .right, state: 0),
                         Rule(write: 0, turn: .left, state: 1)]]
            case .fibonacci:
                return [[Rule(write: 1, turn: .left, state: 1),
                         Rule(write: 1, turn: .left, state: 1)],
                        [Rule(write: 1, turn: .right, state: 1),
                         Rule(write: 0, turn: .straight, state: 0)]]
            }
        }
    }

    /// Grid width and height in cells. The grid wraps at the edges.
    public let columns: Int
    public let rows: Int

    /// How many cell values the rule table writes (the number of colors per state row).
    public let colors: Int

    /// The rule table, `[state][color]`, validated at init.
    public let rules: [[Rule]]

    /// Steps taken so far (each step moves every ant once).
    public private(set) var stepCount: Int = 0

    /// One walker on the grid.
    private struct Ant {
        var column: Int
        var row: Int
        var direction: Int   // 0 up, 1 right, 2 down, 3 left (clockwise quarters)
        var state: Int
    }

    private var grid: [UInt8]   // color per cell, row-major
    private var ants: [Ant]

    /// Make a turmite from a rule table, `[state][color]`. Every state must handle the
    /// same number of colors (at least 2); writes and next-states are clamped into
    /// range. Ants start at the given cells (default: one ant at the center), facing
    /// up; within a step they move in array order, so multi-ant runs stay deterministic.
    public init(rules: [[Rule]], columns: Int, rows: Int,
                ants: [(column: Int, row: Int)]? = nil) {
        let states = max(1, rules.count)
        let colors = max(2, rules.first?.count ?? 2)
        self.columns = max(1, columns)
        self.rows = max(1, rows)
        self.colors = colors
        // Normalize: every state row exactly `colors` wide, targets clamped in range.
        var table: [[Rule]] = []
        for s in 0 ..< states {
            var row = s < rules.count ? rules[s] : []
            if row.count < colors {
                row += Array(repeating: Rule(write: 0, turn: .straight, state: 0),
                             count: colors - row.count)
            } else if row.count > colors {
                row = Array(row.prefix(colors))
            }
            for i in row.indices {
                row[i].write = min(colors - 1, max(0, row[i].write))
                row[i].state = min(states - 1, max(0, row[i].state))
            }
            table.append(row)
        }
        self.rules = table
        let w = self.columns, h = self.rows
        self.grid = [UInt8](repeating: 0, count: w * h)
        let starts = (ants?.isEmpty == false ? ants : nil) ?? [(w / 2, h / 2)]
        self.ants = starts.map {
            Ant(column: (($0.column % w) + w) % w,
                row: (($0.row % h) + h) % h,
                direction: 0, state: 0)
        }
    }

    /// Make one of the known `Preset` turmites.
    public convenience init(_ preset: Preset, columns: Int, rows: Int,
                            ants: [(column: Int, row: Int)]? = nil) {
        self.init(rules: preset.rules, columns: columns, rows: rows, ants: ants)
    }

    /// Advance the machine by `steps` (each step moves every ant once).
    public func step(_ steps: Int = 1) {
        guard steps > 0 else { return }
        for _ in 0 ..< steps {
            for i in ants.indices {
                var ant = ants[i]
                let cell = ant.row * columns + ant.column
                let rule = rules[ant.state][Int(grid[cell])]
                grid[cell] = UInt8(rule.write)
                ant.direction = (ant.direction + rule.turn.quarters) % 4
                switch ant.direction {
                case 0: ant.row = ant.row == 0 ? rows - 1 : ant.row - 1
                case 1: ant.column = ant.column == columns - 1 ? 0 : ant.column + 1
                case 2: ant.row = ant.row == rows - 1 ? 0 : ant.row + 1
                default: ant.column = ant.column == 0 ? columns - 1 : ant.column - 1
                }
                ant.state = rule.state
                ants[i] = ant
            }
            stepCount += 1
        }
    }

    /// The color under a cell, 0 (unpainted) through `colors - 1`. Coordinates wrap.
    public func colorIndex(atColumn column: Int, row: Int) -> Int {
        let c = ((column % columns) + columns) % columns
        let r = ((row % rows) + rows) % rows
        return Int(grid[r * columns + c])
    }

    /// Every non-zero cell, row-major, ready to draw. Rebuilt on each call; for a tight
    /// per-cell loop, read `colorIndex(atColumn:row:)` instead.
    public var paintedCells: [(column: Int, row: Int, color: Int)] {
        var cells: [(column: Int, row: Int, color: Int)] = []
        for r in 0 ..< rows {
            let base = r * columns
            for c in 0 ..< columns where grid[base + c] != 0 {
                cells.append((c, r, Int(grid[base + c])))
            }
        }
        return cells
    }

    /// Where the ants are, in cell coordinates (for drawing a marker on the walkers).
    public var antPositions: [(column: Int, row: Int)] {
        ants.map { ($0.column, $0.row) }
    }
}
