import Foundation

/// Kolam and sona: the line that travels around a grid of dots and closes on
/// itself. One line is launched between the dots at 45 degrees. It runs straight
/// until it meets the edge of the field, bounces, and carries on, and it always
/// comes back to where it started. The drawing is the path.
///
/// The tradition is old and it is not one place's alone. In south India a kolam
/// is chalked on the doorstep at dawn around a grid of pulli (dots); in Angola a
/// sona is drawn in sand with one finger while the story is told. The
/// mathematics under both is the same, and it is exact: over a plain field of
/// `rows` by `columns` dots the line closes into **gcd(rows, columns)** loops,
/// so a 7 by 5 field is one unbroken line and a 6 by 4 field is two.
///
/// A `mirror` is a short wall placed between two neighboring dots. The line
/// cannot cross it, so it bounces there too, and each wall either cuts one loop
/// in two or joins two into one. That is how a drawing is steered toward a
/// single line, and how the figures of a sona are drawn.
///
/// ```swift
/// let design = kolam(columns: 7, rows: 5)
/// noFill(); stroke(.white); strokeWeight(6)
/// for loop in design.loops { drawPolyline(loop.smoothed(3).points, closed: true) }
/// fill(.white); noStroke()
/// for dot in design.dots { drawCircle(center: dot, radius: 4) }
/// ```
public struct Kolam: Equatable, Sendable {

    /// A short wall between two neighboring dots. The line bounces off it
    /// instead of passing between them.
    public struct Mirror: Equatable, Hashable, Sendable {
        /// The dot the wall is placed against, counting from the top-left dot.
        public let column: Int
        public let row: Int
        /// `true` for a wall standing between this dot and the one to its right,
        /// `false` for one lying between this dot and the one below it.
        public let isUpright: Bool

        /// A wall standing between the dot at `column`, `row` and its right
        /// neighbor.
        public static func rightOf(column: Int, row: Int) -> Mirror {
            Mirror(column: column, row: row, isUpright: true)
        }

        /// A wall lying between the dot at `column`, `row` and the one below it.
        public static func below(column: Int, row: Int) -> Mirror {
            Mirror(column: column, row: row, isUpright: false)
        }
    }

    /// The field of dots the line travels around. One dot per cell, so the
    /// grid's `gutter` does not apply: the line needs an even field to bounce in.
    public let grid: Grid
    /// The walls placed between dots. A wall on the outside edge is ignored,
    /// since the edge already turns the line.
    public let mirrors: [Mirror]

    public init(grid: Grid, mirrors: [Mirror] = []) {
        self.grid = grid
        self.mirrors = mirrors
    }

    // MARK: - The two faces

    /// The dots themselves, row-major, for drawing the field the line goes
    /// around. A kolam shows them; a sona usually does not.
    public var dots: [Vector2] { grid.points.map(\.position) }

    /// The line-work: one closed `Contour` per loop, in canvas coordinates,
    /// ready for stroking, the shape booleans, or SVG export. The corners are
    /// square, which is the honest geometry; `Contour.smoothed(_:)` rounds them
    /// into the drawn form.
    ///
    /// With no mirrors there are `gcd(rows, columns)` of them, and however the
    /// walls are placed the loops always hold `4 × rows × columns` segments
    /// between them: four in every cell, one against each of its four sides.
    public var loops: [Contour] {
        let curve = MirrorCurve(columns: grid.columns, rows: grid.rows, mirrors: mirrors)
        return curve.loops.map { walk in
            Contour(walk.map { curve.place($0, in: grid.bounds) }, closed: true)
        }
    }

    /// How many closed loops the line makes. With no mirrors this is
    /// `gcd(rows, columns)`, and one is the drawing a single unbroken line makes.
    public var loopCount: Int { loops.count }
}

// MARK: - The walk under both

/// The mirror-curve walk the kolam line and the knotwork cords are both made
/// of. A line launched between a field of dots at 45 degrees, turning at the
/// edge of the field and at any wall, until it closes on itself.
///
/// The line lives on a lattice twice as fine as the dots: a dot sits at an
/// odd-odd point, and the line only ever touches points where exactly one
/// coordinate is even, which are the gaps between neighboring dots. One step is
/// one diagonal move, so each step crosses one cell.
struct MirrorCurve {
    let columns: Int
    let rows: Int
    /// A wall at a lattice point, indexed `y * stride + x`. The outside edges
    /// are not in here: they turn the line by their own rule.
    private let blocked: [Bool]

    var width: Int { 2 * columns }
    var height: Int { 2 * rows }
    private var stride: Int { width + 1 }

    init(columns: Int, rows: Int, mirrors: [Kolam.Mirror]) {
        self.columns = Swift.max(0, columns)
        self.rows = Swift.max(0, rows)
        let w = 2 * self.columns, h = 2 * self.rows
        var walls = [Bool](repeating: false, count: (w + 1) * (h + 1))
        for mirror in mirrors {
            let x = mirror.isUpright ? 2 * mirror.column + 2 : 2 * mirror.column + 1
            let y = mirror.isUpright ? 2 * mirror.row + 1 : 2 * mirror.row + 2
            // A wall on the outside edge would say nothing the edge does not
            // already say, so it is dropped rather than counted twice.
            guard x > 0, x < w, y > 0, y < h else { continue }
            walls[y * (w + 1) + x] = true
        }
        self.blocked = walls
    }

    /// The direction the line leaves `x`, `y` with, having arrived along `dx`,
    /// `dy`. Exactly one coordinate is even, which is the axis any wall there
    /// stands on, so at most one of the two flips.
    func leaving(_ x: Int, _ y: Int, _ dx: Int, _ dy: Int) -> (Int, Int) {
        guard columns > 0, rows > 0 else { return (dx, dy) }
        if y % 2 == 0 {
            let turn = (y == 0 && dy < 0) || (y == height && dy > 0) || blocked[y * stride + x]
            return (dx, turn ? -dy : dy)
        }
        let turn = (x == 0 && dx < 0) || (x == width && dx > 0) || blocked[y * stride + x]
        return (turn ? -dx : dx, dy)
    }

    /// Every closed loop, as the lattice points it passes through in order.
    var loops: [[SIMD2<Int>]] {
        guard columns > 0, rows > 0 else { return [] }
        let steps = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
        func slot(_ x: Int, _ y: Int, _ dx: Int, _ dy: Int) -> Int {
            ((y * stride + x) * 4) + (dx > 0 ? 0 : 2) + (dy > 0 ? 0 : 1)
        }

        var walked = [Bool](repeating: false, count: stride * (height + 1) * 4)
        var out: [[SIMD2<Int>]] = []
        for startY in 0...height {
            for startX in 0...width where (startX + startY) % 2 == 1 {
                for step in steps {
                    // Only a direction the point can actually be left in: the
                    // reflected ones are the same walk relabeled, and tracing
                    // both would hand back every loop twice.
                    guard leaving(startX, startY, step.0, step.1) == step,
                          !walked[slot(startX, startY, step.0, step.1)] else { continue }

                    var points: [SIMD2<Int>] = []
                    var x = startX, y = startY, (dx, dy) = step
                    repeat {
                        points.append(SIMD2(x, y))
                        let nextX = x + dx, nextY = y + dy
                        let arrived = (dx, dy)
                        (dx, dy) = leaving(nextX, nextY, dx, dy)
                        // The same loop walked backwards is a different set of
                        // states, so both are struck off as the walk passes.
                        walked[slot(nextX, nextY, dx, dy)] = true
                        walked[slot(nextX, nextY, -arrived.0, -arrived.1)] = true
                        x = nextX; y = nextY
                    } while !(x == startX && y == startY && (dx, dy) == step)
                    out.append(points)
                }
            }
        }
        return out
    }

    /// A lattice point placed in `bounds`. The lattice spans the field edge to
    /// edge, and the dots land on its odd-odd points, which is exactly where the
    /// grid puts them.
    func place(_ point: SIMD2<Int>, in bounds: Rectangle) -> Vector2 {
        Vector2(bounds.x + Double(point.x) / Double(width) * bounds.width,
                bounds.y + Double(point.y) / Double(height) * bounds.height)
    }
}

// MARK: - Sketch sugar

public extension Sketch {
    /// A kolam over a `columns × rows` field of dots filling `bounds` (the canvas
    /// by default). Hold the value to draw its `loops` and `dots` yourself, and
    /// to read `loopCount`.
    ///
    /// ```swift
    /// let design = kolam(columns: 7, rows: 5)
    /// for loop in design.loops { drawPolyline(loop.smoothed(3).points, closed: true) }
    /// ```
    func kolam(in bounds: Rectangle? = nil, columns: Int, rows: Int,
               mirrors: [Kolam.Mirror] = []) -> Kolam {
        Kolam(grid: Grid(in: bounds ?? self.bounds, columns: columns, rows: rows),
              mirrors: mirrors)
    }

    /// Draw a kolam's line-work with the current `stroke`, rounded by `rounding`
    /// passes of corner cutting (2 is the drawn look, 0 the square lattice path).
    /// The dots are not drawn: a kolam shows them, a sona does not, so that is
    /// yours to decide.
    func drawKolam(in bounds: Rectangle? = nil, columns: Int, rows: Int,
                   mirrors: [Kolam.Mirror] = [], rounding: Int = 2) {
        for loop in kolam(in: bounds, columns: columns, rows: rows, mirrors: mirrors).loops {
            drawPolyline(loop.smoothed(iterations: rounding).points, closed: true)
        }
    }
}
