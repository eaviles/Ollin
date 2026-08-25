import Foundation

/// A padding inset on each edge of a rectangle, in sketch points.
///
/// The currency for `Grid` margins and `Rectangle.inset(by:)`. Build it the way
/// the layout reads: `.all(20)`, `.symmetric(horizontal: 40, vertical: 20)`,
/// `.horizontal(40)`, `.vertical(20)`, or the explicit
/// `Insets(top:right:bottom:left:)`. A bare number works too: `padding: 20`
/// reads as `.all(20)`.
public struct Insets: Equatable, Hashable, Sendable, Codable {
    public var top: Double
    public var right: Double
    public var bottom: Double
    public var left: Double

    public init(top: Double = 0, right: Double = 0, bottom: Double = 0, left: Double = 0) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }

    /// No inset.
    public static let zero = Insets()

    /// The same inset on all four edges.
    public static func all(_ value: Double) -> Insets {
        Insets(top: value, right: value, bottom: value, left: value)
    }

    /// `horizontal` on the left and right edges, `vertical` on the top and bottom.
    public static func symmetric(horizontal: Double = 0, vertical: Double = 0) -> Insets {
        Insets(top: vertical, right: horizontal, bottom: vertical, left: horizontal)
    }

    /// The same inset on the left and right edges only.
    public static func horizontal(_ value: Double) -> Insets {
        Insets(right: value, left: value)
    }

    /// The same inset on the top and bottom edges only.
    public static func vertical(_ value: Double) -> Insets {
        Insets(top: value, bottom: value)
    }
}

extension Insets: ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral {
    /// A bare number is an even inset on every edge, so `padding: 20` reads as `.all(20)`.
    public init(integerLiteral value: Int) { self = .all(Double(value)) }
    public init(floatLiteral value: Double) { self = .all(value) }
}

public extension Rectangle {
    /// This rectangle shrunk inward by `insets` (clamped so it never inverts to a
    /// negative size).
    func inset(by insets: Insets) -> Rectangle {
        let w = Swift.max(0, width - insets.left - insets.right)
        let h = Swift.max(0, height - insets.top - insets.bottom)
        return Rectangle(x: x + insets.left, y: y + insets.top, width: w, height: h)
    }
}

/// A regular grid of `columns × rows` over a rectangle.
///
/// `Grid` is geometry, not a draw call. It gives you two things, and you loop
/// whichever you're drawing. Each element carries its `column`/`row`, so one loop
/// covers the indexed cases too (a checkerboard, a hue by position) without a
/// nested `for`:
///
/// - **`points`** are the dots (`[Point]`: `column`, `row`, `position`).
/// - **`cells`** are the cell rectangles (`[Cell]`: `column`, `row`, `center`, `frame`).
///
///       for p in grid.points {                          // dots
///           drawCircle(center: p.position, radius: 6)
///       }
///       for c in grid.cells {                           // cells, with indices
///           fill((c.column + c.row) % 2 == 0 ? .white : .black)
///           drawRect(c.frame)
///       }
///
/// `padding` insets the whole grid from the rectangle's edges; `gutter` is the
/// gap *between* cells. Grids nest, since a cell is just another `Rectangle`:
/// `for c in grid.cells { Grid(in: c.frame, columns: 3, rows: 3) }`.
public struct Grid: Equatable, Hashable, Sendable {
    /// Where a grid's `points` sit. `cells` (the tiling rectangles) are unaffected.
    public enum Distribution: Sendable, Equatable, Hashable {
        /// One dot at the center of each cell: `columns × rows` dots inset half a
        /// cell from the edges, each at its cell's center. The default: "a thing in
        /// every cell".
        case center
        /// `columns × rows` dots spanning the bounds edge to edge, the outer ones
        /// sit on the boundary (the four corner dots at the rectangle's corners), so
        /// the dots reach the edges. Spacing is `size / (count − 1)`. The lattice
        /// layout for a grid *of dots*. (`gutter` doesn't apply: spanning dots span
        /// the full bounds.)
        case spanning
    }

    /// One cell of a `Grid`: its zero-based `column`/`row`, its true `center`, and
    /// its `frame` rectangle.
    public struct Cell: Equatable, Hashable, Sendable {
        public let column: Int
        public let row: Int
        public let center: Vector2
        public let frame: Rectangle
    }

    /// One dot of a `Grid`: its zero-based `column`/`row` and its `position` (laid
    /// out per the grid's `distribution`).
    public struct Point: Equatable, Hashable, Sendable {
        public let column: Int
        public let row: Int
        public let position: Vector2
    }

    /// The region the cells fill (`bounds` after `padding` was applied).
    public let bounds: Rectangle
    public let columns: Int
    public let rows: Int
    /// The gap between adjacent cells, in sketch points (0 = cells touch).
    public let gutter: Double
    /// How `points` are laid out: a dot per cell (`.center`) or a lattice spanning
    /// the edges (`.spanning`).
    public let distribution: Distribution

    /// Lay a `columns × rows` grid inside `rectangle`, first inset by `padding`,
    /// with `gutter` points of space between adjacent cells. `distribution`
    /// chooses how the `points` fall: a dot per cell (`.center`, the default) or a
    /// lattice spanning the edges (`.spanning`).
    public init(in rectangle: Rectangle, columns: Int, rows: Int,
                padding: Insets = .zero, gutter: Double = 0,
                distribution: Distribution = .center) {
        self.bounds = rectangle.inset(by: padding)
        self.columns = Swift.max(0, columns)
        self.rows = Swift.max(0, rows)
        self.gutter = Swift.max(0, gutter)
        self.distribution = distribution
    }

    /// The width of one cell (the `gutter` taken out of the bounds first).
    public var cellWidth: Double {
        columns > 0 ? Swift.max(0, (bounds.width - gutter * Double(columns - 1)) / Double(columns)) : 0
    }
    /// The height of one cell (the `gutter` taken out of the bounds first).
    public var cellHeight: Double {
        rows > 0 ? Swift.max(0, (bounds.height - gutter * Double(rows - 1)) / Double(rows)) : 0
    }
    /// One cell's size as a vector.
    public var cellSize: Vector2 { Vector2(cellWidth, cellHeight) }

    /// The cell at zero-based `column`, `row`.
    public func cell(column: Int, row: Int) -> Cell {
        let frame = Rectangle(x: bounds.x + Double(column) * (cellWidth + gutter),
                              y: bounds.y + Double(row) * (cellHeight + gutter),
                              width: cellWidth, height: cellHeight)
        return Cell(column: column, row: row, center: frame.center, frame: frame)
    }

    /// The dot at zero-based `column`, `row`, laid out per the grid's `distribution`.
    public func point(column: Int, row: Int) -> Point {
        let position: Vector2
        switch distribution {
        case .center:
            position = cell(column: column, row: row).center
        case .spanning:
            let fx = columns > 1 ? Double(column) / Double(columns - 1) : 0.5
            let fy = rows > 1 ? Double(row) / Double(rows - 1) : 0.5
            position = Vector2(bounds.x + fx * bounds.width, bounds.y + fy * bounds.height)
        }
        return Point(column: column, row: row, position: position)
    }

    /// Every dot, row-major (left to right, top to bottom), laid out per the
    /// grid's `distribution`. Loop this to draw a mark at each.
    public var points: [Point] {
        var out = [Point]()
        out.reserveCapacity(columns * rows)
        for row in 0..<rows {
            for column in 0..<columns { out.append(point(column: column, row: row)) }
        }
        return out
    }

    /// Every cell, row-major. Loop this to draw into each.
    public var cells: [Cell] {
        var out = [Cell]()
        out.reserveCapacity(columns * rows)
        for row in 0..<rows {
            for column in 0..<columns { out.append(cell(column: column, row: row)) }
        }
        return out
    }
}

// MARK: - Sketch sugar

public extension Sketch {
    /// A `columns × rows` grid over the whole canvas, inset by `padding`, with
    /// `gutter` points of space between cells.
    ///
    /// The bare entry point: `grid(columns: 20, rows: 20, padding: 40)`. Pass
    /// `distribution: .spanning` for a grid *of dots* that reach the edges. For a
    /// sub-region (a render target, or a single cell subdivided further), build
    /// `Grid(in: someRectangle, …)` directly.
    func grid(columns: Int, rows: Int, padding: Insets = .zero, gutter: Double = 0,
              distribution: Grid.Distribution = .center) -> Grid {
        Grid(in: bounds, columns: columns, rows: rows,
             padding: padding, gutter: gutter, distribution: distribution)
    }

    /// Draw a labeled sheet of tiles: the items laid into a near-square grid
    /// over the whole canvas, `tile` drawing each one into its cell, and each
    /// cell wearing its label on a dark plate along its bottom edge. The
    /// gallery layout a comparison sketch keeps rebuilding by hand:
    ///
    /// ```swift
    /// drawSheet(filters.map { ($0.name, $0) }) { filter, cell in
    ///     drawImage(scene.filtered(filter).image, in: cell)
    /// }
    /// ```
    ///
    /// `columns` left out picks the near-square count (the ceiling of the
    /// square root); `gutter` defaults to 1% of the canvas width. Labels use
    /// the current `textFont`, sized to the column count, and the drawing
    /// state around the call is untouched. An empty list draws nothing.
    func drawSheet<Item>(_ items: [(String, Item)], columns: Int? = nil,
                         gutter: Double? = nil, _ tile: (Item, Rectangle) -> Void) {
        guard !items.isEmpty else { return }
        let cols = max(1, columns ?? Int(Double(items.count).squareRoot().rounded(.up)))
        let rows = (items.count + cols - 1) / cols
        let space = gutter ?? width * 0.01
        let cellW = (width - space * Double(cols + 1)) / Double(cols)
        let cellH = (height - space * Double(rows + 1)) / Double(rows)
        let labelSize = cols >= 4 ? 13.0 : 17.0
        let plate = cols >= 4 ? 22.0 : 30.0
        for (i, item) in items.enumerated() {
            let cell = Rectangle(x: space + Double(i % cols) * (cellW + space),
                                 y: space + Double(i / cols) * (cellH + space),
                                 width: cellW, height: cellH)
            tile(item.1, cell)
            withState {
                blendMode(.normal)
                noStroke()
                fill(Color(white: 0, alpha: 0.55))
                drawRect(cell.x, cell.y + cell.height - plate, cell.width, plate)
                drawText(item.0, cell.x + 8, cell.y + cell.height - plate / 2,
                         size: labelSize, color: .white, align: .left, .middle)
            }
        }
    }
}
