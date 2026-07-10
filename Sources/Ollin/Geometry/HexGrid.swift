import Foundation

/// A regular hexagon grid of `columns × rows` cells laid over a rectangle: the
/// honeycomb sibling of `Grid`.
///
/// Like `Grid`, it's geometry, not a draw call: loop `cells` and draw whatever
/// each cell suggests. Every `Cell` carries its `column`/`row` (the rectangular
/// storage address) *and* its axial `q`/`r` (the hex-native coordinates the
/// math helpers use), plus its `center` and ready-to-draw `corners`:
///
///     let hexes = hexGrid(columns: 12, rows: 10, padding: 40)
///     for cell in hexes.cells {
///         fill(Color(hue: Double(hexes.distance(from: hexes.cells[60], to: cell)) * 0.09,
///                    saturation: 0.6, brightness: 0.9))
///         drawPolygon(cell.corners)
///     }
///
/// The hexagons keep their true aspect (a hex can't stretch the way a `Grid`
/// cell can), so the block is sized to fit inside the padded bounds and
/// centered: ask for more `columns` for smaller hexes. `gutter` opens a gap
/// between neighbors; `orientation` picks pointy-top (rows shift by half a
/// hex) or flat-top (columns shift). Hex-native math rides the axial
/// coordinates: `distance(from:to:)` (rings of equal distance make the classic
/// honeycomb falloff), `neighbors(of:)` (up to six), `ring(around:radius:)`,
/// and `cell(at:)` for exact mouse-to-hex picking.
public struct HexGrid: Equatable, Hashable, Sendable {
    /// Which way a hexagon points. `.pointy` puts a corner at the top (rows
    /// shift by half a hex); `.flat` puts an edge at the top (columns shift).
    public enum Orientation: Sendable, Equatable, Hashable, CaseIterable {
        case pointy
        case flat
    }

    /// One hexagon of a `HexGrid`: its zero-based `column`/`row` storage
    /// address, its axial `q`/`r` (what the distance/neighbor math uses), its
    /// `center`, its corner `radius`, and its six `corners` ready for
    /// `drawPolygon`.
    public struct Cell: Equatable, Hashable, Sendable {
        public let column: Int
        public let row: Int
        /// Axial column: constant along one of the three lattice directions.
        public let q: Int
        /// Axial row: constant along another lattice direction.
        public let r: Int
        public let center: Vector2
        /// Center-to-corner distance (after `gutter` is taken out).
        public let radius: Double
        /// The six corners in drawing order.
        public let corners: [Vector2]

        /// The hexagon as a closed `Contour`.
        public var contour: Contour { Contour(corners, closed: true) }
    }

    /// The region the grid was fit into (`bounds` after `padding`).
    public let bounds: Rectangle
    public let columns: Int
    public let rows: Int
    public let orientation: Orientation
    /// The gap between adjacent hexagons, in sketch points (0 = edges touch).
    public let gutter: Double
    /// The full center-to-corner size of one lattice hex (before `gutter`
    /// shrinks the drawn cell).
    public let hexSize: Double

    /// Where the center of cell `(0, 0)` sits (the block is centered in `bounds`).
    private let firstCenter: Vector2

    /// Lay a `columns × rows` hex grid inside `rectangle`, first inset by
    /// `padding`, with `gutter` points of gap between neighboring hexagons.
    /// The block of hexes keeps its true aspect: it's sized to the tighter of
    /// the two fits and centered in the padded bounds.
    public init(in rectangle: Rectangle, columns: Int, rows: Int,
                orientation: Orientation = .pointy,
                padding: Insets = .zero, gutter: Double = 0) {
        let bounds = rectangle.inset(by: padding)
        self.bounds = bounds
        self.columns = Swift.max(1, columns)
        self.rows = Swift.max(1, rows)
        self.orientation = orientation
        self.gutter = Swift.max(0, gutter)

        // Block extents in units of the hex size: alternate rows (pointy) or
        // columns (flat) shift by half a spacing, widening the block by half a
        // hex when there is more than one of them.
        let c = Double(self.columns), r = Double(self.rows)
        let root3 = 3.0.squareRoot()
        let wUnits: Double, hUnits: Double
        switch orientation {
        case .pointy:
            wUnits = root3 * (c + (self.rows > 1 ? 0.5 : 0))
            hUnits = 1.5 * r + 0.5
        case .flat:
            wUnits = 1.5 * c + 0.5
            hUnits = root3 * (r + (self.columns > 1 ? 0.5 : 0))
        }
        let size = Swift.max(0, Swift.min(bounds.width / wUnits, bounds.height / hUnits))
        self.hexSize = size

        // Center the block, then step in half a hex to the first center.
        let block = Vector2(wUnits * size, hUnits * size)
        let origin = Vector2(bounds.x + (bounds.width - block.x) / 2,
                             bounds.y + (bounds.height - block.y) / 2)
        switch orientation {
        case .pointy:
            firstCenter = Vector2(origin.x + root3 / 2 * size, origin.y + size)
        case .flat:
            firstCenter = Vector2(origin.x + size, origin.y + root3 / 2 * size)
        }
    }

    // MARK: - Cells

    /// The cell at zero-based storage `column`, `row`.
    public func cell(column: Int, row: Int) -> Cell {
        let root3 = 3.0.squareRoot()
        let center: Vector2
        let q: Int, r: Int
        switch orientation {
        case .pointy:
            // Odd rows shift right by half a spacing.
            center = Vector2(firstCenter.x + root3 * hexSize * (Double(column) + 0.5 * Double(row & 1)),
                             firstCenter.y + 1.5 * hexSize * Double(row))
            q = column - (row - (row & 1)) / 2
            r = row
        case .flat:
            // Odd columns shift down by half a spacing.
            center = Vector2(firstCenter.x + 1.5 * hexSize * Double(column),
                             firstCenter.y + root3 * hexSize * (Double(row) + 0.5 * Double(column & 1)))
            q = column
            r = row - (column - (column & 1)) / 2
        }
        // A gutter of g between edges pulls each corner in by g/√3 (the
        // apothem shrinks by g/2 on each side of the shared edge).
        let radius = Swift.max(0, hexSize - gutter / root3)
        let startAngle = orientation == .pointy ? -Double.pi / 6 : 0
        let corners = (0..<6).map { i -> Vector2 in
            let angle = startAngle + Double(i) * .pi / 3
            return Vector2(center.x + radius * cos(angle), center.y + radius * sin(angle))
        }
        return Cell(column: column, row: row, q: q, r: r,
                    center: center, radius: radius, corners: corners)
    }

    /// Every cell, row-major (left to right, top to bottom).
    public var cells: [Cell] {
        var out = [Cell]()
        out.reserveCapacity(columns * rows)
        for row in 0..<rows {
            for column in 0..<columns { out.append(cell(column: column, row: row)) }
        }
        return out
    }

    /// The cell holding axial coordinates `q`, `r`, or nil when it falls
    /// outside the grid.
    public func cell(q: Int, r: Int) -> Cell? {
        let column: Int, row: Int
        switch orientation {
        case .pointy:
            column = q + (r - (r & 1)) / 2
            row = r
        case .flat:
            column = q
            row = r + (q - (q & 1)) / 2
        }
        guard column >= 0, column < columns, row >= 0, row < rows else { return nil }
        return cell(column: column, row: row)
    }

    /// The cell whose hexagon contains `point`, or nil outside the grid: exact
    /// hex picking (fractional axial coordinates snapped by cube rounding), so
    /// mouse-to-hex is one call.
    public func cell(at point: Vector2) -> Cell? {
        guard hexSize > 0 else { return nil }
        let root3 = 3.0.squareRoot()
        let x = point.x - firstCenter.x, y = point.y - firstCenter.y
        let fq: Double, fr: Double
        switch orientation {
        case .pointy:
            fq = (root3 / 3 * x - y / 3) / hexSize
            fr = (2.0 / 3 * y) / hexSize
        case .flat:
            fq = (2.0 / 3 * x) / hexSize
            fr = (-x / 3 + root3 / 3 * y) / hexSize
        }
        // Cube rounding: round all three, then recompute the worst offender so
        // q + r + s stays 0 (rounding each independently drifts off the lattice
        // near edges and corners).
        let fs = -fq - fr
        var q = fq.rounded(), r = fr.rounded()
        let s = fs.rounded()
        let dq = abs(q - fq), dr = abs(r - fr), ds = abs(s - fs)
        if dq > dr && dq > ds {
            q = -r - s
        } else if dr > ds {
            r = -q - s
        }
        return cell(q: Int(q), r: Int(r))
    }

    // MARK: - Hex math

    /// How many hexes apart two cells are (the least number of neighbor steps).
    public func distance(from a: Cell, to b: Cell) -> Int {
        let dq = a.q - b.q, dr = a.r - b.r
        return (abs(dq) + abs(dq + dr) + abs(dr)) / 2
    }

    /// The up-to-six cells sharing an edge with `cell` (fewer at the grid's
    /// rim).
    public func neighbors(of cell: Cell) -> [Cell] {
        Self.axialDirections.compactMap { self.cell(q: cell.q + $0.dq, r: cell.r + $0.dr) }
    }

    /// The cells exactly `radius` hexes from `center`, walking the ring in
    /// order (cells falling outside the grid are skipped). `radius` 0 is the
    /// center itself.
    public func ring(around center: Cell, radius: Int) -> [Cell] {
        guard radius > 0 else { return radius == 0 ? [cell(q: center.q, r: center.r)].compactMap { $0 } : [] }
        var out: [Cell] = []
        // Start radius steps along one direction, then walk radius steps in
        // each of the six directions in turn.
        var q = center.q + Self.axialDirections[4].dq * radius
        var r = center.r + Self.axialDirections[4].dr * radius
        for direction in Self.axialDirections {
            for _ in 0..<radius {
                if let c = cell(q: q, r: r) { out.append(c) }
                q += direction.dq
                r += direction.dr
            }
        }
        return out
    }

    /// The six axial direction offsets, in ring-walk order.
    private static let axialDirections: [(dq: Int, dr: Int)] = [
        (1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1),
    ]
}

// MARK: - Sketch sugar

public extension Sketch {
    /// A `columns × rows` hexagon grid over the whole canvas, inset by
    /// `padding`, with `gutter` points of gap between neighbors. The bare entry
    /// point: `hexGrid(columns: 12, rows: 10)`. For a sub-region, build
    /// `HexGrid(in: someRectangle, …)` directly.
    func hexGrid(columns: Int, rows: Int,
                 orientation: HexGrid.Orientation = .pointy,
                 padding: Insets = .zero, gutter: Double = 0) -> HexGrid {
        HexGrid(in: bounds, columns: columns, rows: rows,
                orientation: orientation, padding: padding, gutter: gutter)
    }
}
