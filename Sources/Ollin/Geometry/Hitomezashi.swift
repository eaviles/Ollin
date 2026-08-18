import Foundation

/// Hitomezashi stitching: the one-stitch sashiko pattern. Every line of a grid
/// carries a row of unit dashes, and one bit per line decides whether its dashes
/// start on the edge or one cell in. Because neighboring lines shift against
/// each other, the dashes join at the grid's crossings into steps, staircases,
/// and closed loops, and a handful of coin flips reads as a woven design.
///
/// The whole design is those bits: one per horizontal line (top to bottom) and
/// one per vertical line (left to right). Shorter bit arrays repeat, so a small
/// motif tiles a large cloth. The seeded form flips each bit with `probability`,
/// so the same seed always stitches the same design.
///
/// Two faces come out of one design:
///
/// - `stitches` is the line-work, one open two-point `Contour` per dash, ready
///   for stroking, the shape booleans, hatching, or SVG export.
/// - `parities` two-colors the cells. Every hitomezashi design splits the cloth
///   into regions a checkerboard of two tones can fill exactly, and this is
///   that coloring, row-major so it zips with `grid.cells`.
///
/// ```swift
/// seed(5)
/// let design = hitomezashi(columns: 24, rows: 24)
/// stroke(.white); strokeWeight(4); strokeCap(.round)
/// for dash in design.stitches { drawPolyline(dash.points) }
/// ```
public struct Hitomezashi: Equatable, Sendable {
    /// The grid whose lines carry the stitching. Its `gutter` does not apply:
    /// stitches run along the continuous grid lines.
    public let grid: Grid
    /// One bit per horizontal line, top to bottom (`rows + 1` lines; shorter
    /// arrays repeat, an empty array reads as all `false`). `false` starts the
    /// line's dashes at the left edge; `true` starts them one cell in.
    public let rowBits: [Bool]
    /// One bit per vertical line, left to right (`columns + 1` lines; shorter
    /// arrays repeat, an empty array reads as all `false`). `false` starts the
    /// line's dashes at the top edge; `true` starts them one cell down.
    public let columnBits: [Bool]

    /// A design from explicit bits, for hand-authored or encoded patterns
    /// (bits from a word, a date, a name). Shorter bit arrays repeat along
    /// their lines.
    public init(grid: Grid, rowBits: [Bool], columnBits: [Bool]) {
        self.grid = grid
        self.rowBits = rowBits
        self.columnBits = columnBits
    }

    /// A design whose bits are drawn from `rng`, each `true` with
    /// `probability`. At `0.5` the classic balanced weave; biased toward 0 or 1
    /// the design drifts into long diagonal staircases.
    public init<R: RandomNumberGenerator>(grid: Grid, probability: Double = 0.5,
                                          using rng: inout R) {
        let p = min(max(probability, 0), 1)
        self.grid = grid
        self.rowBits = (0...grid.rows).map { _ in Double.random(in: 0..<1, using: &rng) < p }
        self.columnBits = (0...grid.columns).map { _ in Double.random(in: 0..<1, using: &rng) < p }
    }

    // MARK: - The two faces

    /// The line-work: one open two-point `Contour` per stitch. On every line
    /// dashes cover alternating cells, so two stitches on the same line never
    /// touch; stitches on neighboring lines meet at the grid's crossings, and
    /// those meetings are the design.
    public var stitches: [Contour] {
        let columns = grid.columns, rows = grid.rows
        guard columns > 0, rows > 0 else { return [] }
        var out: [Contour] = []
        out.reserveCapacity((rows + 1) * ((columns + 1) / 2) + (columns + 1) * ((rows + 1) / 2))
        for line in 0...rows {
            let y = self.y(of: line)
            for cell in 0..<columns where horizontalDash(at: cell, line: line) {
                out.append(Contour([Vector2(x(of: cell), y), Vector2(x(of: cell + 1), y)],
                                   closed: false))
            }
        }
        for line in 0...columns {
            let x = self.x(of: line)
            for cell in 0..<rows where verticalDash(at: cell, line: line) {
                out.append(Contour([Vector2(x, y(of: cell)), Vector2(x, y(of: cell + 1))],
                                   closed: false))
            }
        }
        return out
    }

    /// The two-coloring of the cells, row-major so it zips with `grid.cells`.
    /// Two side-by-side cells get different values exactly when a stitch
    /// separates them, and every hitomezashi design admits this coloring, so
    /// filling by parity paints the design's regions in two tones with no
    /// seams.
    ///
    /// ```swift
    /// for (cell, tone) in zip(design.grid.cells, design.parities) {
    ///     fill(tone ? .black : .white)
    ///     drawRect(cell.frame)
    /// }
    /// ```
    public var parities: [Bool] {
        let columns = grid.columns, rows = grid.rows
        guard columns > 0, rows > 0 else { return [] }
        var out = [Bool](repeating: false, count: columns * rows)
        // The first row walks left to right, flipping across each vertical
        // stitch; every later cell flips down across its horizontal stitch.
        // The design's alternation makes every path between two cells agree,
        // so these two sweeps color every region consistently.
        for column in 1..<columns {
            out[column] = out[column - 1] != verticalDash(at: 0, line: column)
        }
        for row in 1..<rows {
            for column in 0..<columns {
                out[row * columns + column] =
                    out[(row - 1) * columns + column] != horizontalDash(at: column, line: row)
            }
        }
        return out
    }

    // MARK: - Dash rules

    /// The bit for a line, with shorter arrays repeating and an empty array
    /// reading as all `false`.
    private static func bit(_ bits: [Bool], at line: Int) -> Bool {
        bits.isEmpty ? false : bits[line % bits.count]
    }

    /// Whether horizontal line `line` (0 is the top edge) carries a dash over
    /// cell column `cell`: dashes cover alternating cells, and the line's bit
    /// picks which alternation.
    private func horizontalDash(at cell: Int, line: Int) -> Bool {
        (cell + (Self.bit(rowBits, at: line) ? 1 : 0)).isMultiple(of: 2)
    }

    /// Whether vertical line `line` (0 is the left edge) carries a dash over
    /// cell row `cell`.
    private func verticalDash(at cell: Int, line: Int) -> Bool {
        (cell + (Self.bit(columnBits, at: line) ? 1 : 0)).isMultiple(of: 2)
    }

    /// The x of vertical line `line`, spanning the grid's bounds edge to edge.
    private func x(of line: Int) -> Double {
        grid.bounds.x + grid.bounds.width * Double(line) / Double(grid.columns)
    }

    /// The y of horizontal line `line`, spanning the grid's bounds edge to edge.
    private func y(of line: Int) -> Double {
        grid.bounds.y + grid.bounds.height * Double(line) / Double(grid.rows)
    }
}

// MARK: - Sketch sugar

public extension Sketch {
    /// A hitomezashi stitch design over a `columns × rows` grid of `bounds`
    /// (the whole canvas by default), every line's bit flipped by the seeded
    /// `random` with `probability`, so `seed(_:)` makes the design
    /// reproducible. Read `.stitches` for the dashes and `.parities` for the
    /// two-tone fill; for the plain case, `drawHitomezashi` strokes the
    /// stitches for you.
    ///
    /// ```swift
    /// seed(5)
    /// let design = hitomezashi(columns: 24, rows: 24)
    /// for (cell, tone) in zip(design.grid.cells, design.parities) {
    ///     fill(tone ? Color(hex: 0x1B2A49) : Color(hex: 0xF2E9DC))
    ///     drawRect(cell.frame)
    /// }
    /// stroke(.white); strokeWeight(4); strokeCap(.round)
    /// for dash in design.stitches { drawPolyline(dash.points) }
    /// ```
    func hitomezashi(in bounds: Rectangle? = nil, columns: Int, rows: Int,
                     probability: Double = 0.5) -> Hitomezashi {
        let grid = Grid(in: bounds ?? self.bounds, columns: columns, rows: rows)
        return Hitomezashi(grid: grid, probability: probability, using: &rng)
    }

    /// Draw a hitomezashi stitch design over a `columns × rows` grid of
    /// `bounds` (the canvas by default) with the current `stroke`. For the
    /// two-tone fill or per-stitch color, hold the `hitomezashi(…)` value and
    /// draw its faces yourself.
    func drawHitomezashi(in bounds: Rectangle? = nil, columns: Int, rows: Int,
                         probability: Double = 0.5) {
        for dash in hitomezashi(in: bounds, columns: columns, rows: rows,
                                probability: probability).stitches {
            drawPolyline(dash.points, closed: false)
        }
    }
}
