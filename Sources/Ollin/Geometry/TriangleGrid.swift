import Foundation

/// A grid of equilateral triangles laid over a rectangle: alternating
/// up- and down-pointing cells that tile each row edge to edge, the third
/// regular tiling beside `Grid`'s squares and `HexGrid`'s hexagons.
///
/// Like its siblings it's geometry, not a draw call. Each `Cell` carries its
/// `column`/`row`, which way it points, its `center`, and its three `vertices`
/// ready for `drawPolygon`:
///
///     let tris = triangleGrid(columns: 16, rows: 9, padding: 40)
///     for cell in tris.cells {
///         fill(cell.pointsUp ? .white : .black)
///         drawPolygon(cell.vertices)
///     }
///
/// `columns` counts triangles per row; each one advances half an edge length,
/// so neighbors share alternating edges (cell `(column, row)` points up when
/// `column + row` is even). The triangles stay equilateral, so the block is
/// sized to fit the padded bounds and centered; `gutter` opens a gap between
/// neighbors by shrinking each triangle toward its center.
public struct TriangleGrid: Equatable, Hashable, Sendable {
    /// One triangle of a `TriangleGrid`: its zero-based `column`/`row`, which
    /// way it points, its `center` (the centroid), and its three `vertices` in
    /// drawing order.
    public struct Cell: Equatable, Hashable, Sendable {
        public let column: Int
        public let row: Int
        /// Whether the triangle points up (apex at the top). Alternates along
        /// each row and flips row to row: up when `column + row` is even.
        public let pointsUp: Bool
        public let center: Vector2
        /// The three corners in drawing order.
        public let vertices: [Vector2]

        /// The triangle as a closed `Contour`.
        public var contour: Contour { Contour(vertices, closed: true) }
    }

    /// The region the grid was fit into (`bounds` after `padding`).
    public let bounds: Rectangle
    public let columns: Int
    public let rows: Int
    /// The gap between adjacent triangles, in sketch points (0 = edges touch).
    public let gutter: Double
    /// The side length of one lattice triangle (before `gutter` shrinks the
    /// drawn cell).
    public let edgeLength: Double

    /// The top-left corner of the centered block of triangles.
    private let origin: Vector2

    /// Lay a `columns × rows` triangle grid inside `rectangle`, first inset by
    /// `padding`, with `gutter` points of gap between neighbors. The triangles
    /// stay equilateral: the block is sized to the tighter fit and centered in
    /// the padded bounds.
    public init(in rectangle: Rectangle, columns: Int, rows: Int,
                padding: Insets = .zero, gutter: Double = 0) {
        let bounds = rectangle.inset(by: padding)
        self.bounds = bounds
        self.columns = Swift.max(1, columns)
        self.rows = Swift.max(1, rows)
        self.gutter = Swift.max(0, gutter)

        // A row of C triangles spans (C + 1) half-edges; R rows stack R
        // triangle heights (h = √3/2 · edge).
        let root3 = 3.0.squareRoot()
        let c = Double(self.columns), r = Double(self.rows)
        let edge = Swift.max(0, Swift.min(2 * bounds.width / (c + 1),
                                          2 * bounds.height / (root3 * r)))
        self.edgeLength = edge
        let block = Vector2((c + 1) * edge / 2, root3 / 2 * edge * r)
        self.origin = Vector2(bounds.x + (bounds.width - block.x) / 2,
                              bounds.y + (bounds.height - block.y) / 2)
    }

    /// The height of one triangle row.
    public var rowHeight: Double { 3.0.squareRoot() / 2 * edgeLength }

    // MARK: - Cells

    /// The cell at zero-based `column`, `row`.
    public func cell(column: Int, row: Int) -> Cell {
        let e = edgeLength, h = rowHeight
        let up = (column + row) % 2 == 0
        let left = origin.x + Double(column) * e / 2
        let top = origin.y + Double(row) * h
        let bottom = top + h
        var vertices: [Vector2]
        if up {
            vertices = [Vector2(left, bottom), Vector2(left + e, bottom), Vector2(left + e / 2, top)]
        } else {
            vertices = [Vector2(left, top), Vector2(left + e, top), Vector2(left + e / 2, bottom)]
        }
        let center = Vector2((vertices[0].x + vertices[1].x + vertices[2].x) / 3,
                             (vertices[0].y + vertices[1].y + vertices[2].y) / 3)
        if gutter > 0, e > 0 {
            // Pulling each vertex toward the center (the incenter, for an
            // equilateral triangle) by this factor insets every edge by half
            // the gutter, so neighbors end up a full gutter apart.
            let inradius = e * 3.0.squareRoot() / 6
            let k = Swift.max(0, (inradius - gutter / 2) / inradius)
            vertices = vertices.map {
                Vector2(center.x + ($0.x - center.x) * k, center.y + ($0.y - center.y) * k)
            }
        }
        return Cell(column: column, row: row, pointsUp: up, center: center, vertices: vertices)
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

    /// The up-to-three cells sharing an edge with `cell` (fewer at the grid's
    /// rim): its left and right neighbors, plus the row below (for an
    /// up-pointing cell) or above (down-pointing).
    public func neighbors(of cell: Cell) -> [Cell] {
        var out: [Cell] = []
        let across = cell.pointsUp ? cell.row + 1 : cell.row - 1
        let candidates = [(cell.column - 1, cell.row),
                          (cell.column + 1, cell.row),
                          (cell.column, across)]
        for (c, r) in candidates where c >= 0 && c < columns && r >= 0 && r < rows {
            out.append(self.cell(column: c, row: r))
        }
        return out
    }
}

// MARK: - Sketch sugar

public extension Sketch {
    /// A `columns × rows` triangle grid over the whole canvas, inset by
    /// `padding`, with `gutter` points of gap between neighbors. The bare
    /// entry point: `triangleGrid(columns: 16, rows: 9)`. For a sub-region,
    /// build `TriangleGrid(in: someRectangle, …)` directly.
    func triangleGrid(columns: Int, rows: Int,
                      padding: Insets = .zero, gutter: Double = 0) -> TriangleGrid {
        TriangleGrid(in: bounds, columns: columns, rows: rows,
                     padding: padding, gutter: gutter)
    }
}
