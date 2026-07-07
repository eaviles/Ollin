import Foundation

/// Truchet tiling: place one small tile on every cell of a grid, but spin each
/// to a random orientation. Because the tile's marks always meet the cell edges
/// at the same points, the random spins line up across borders and a wall of
/// identical parts reads as one flowing, connected pattern.
///
/// Two tiles are built in, each with two orientations chosen per cell by the
/// seeded `random`, so the same seed always lays out the same pattern:
///
/// - `.arcs` joins each cell's edge midpoints with two quarter-circles, so the
///   arcs meet across borders into smooth meandering loops.
/// - `.diagonals` draws one corner-to-corner diagonal per cell, so the cells
///   read as a maze of corridors.
///
/// The output is a set of open `Contour`s (the line-work), so it feeds straight
/// into stroking, the shape booleans, hatching, and SVG export.
///
/// ```swift
/// var rng = SplitMix64(seed: 3)
/// let grid = Grid(in: bounds, columns: 12, rows: 12)
/// stroke(.white); strokeWeight(8); noFill(); strokeCap(.round)
/// for c in Truchet.contours(grid: grid, tile: .arcs, using: &rng) {
///     drawPolyline(c.points)
/// }
/// ```
public enum Truchet {
    /// A built-in tile, each with two seed-chosen orientations.
    public enum Tile: Sendable, CaseIterable {
        /// Two quarter-circle arcs joining the cell's edge midpoints; they meet
        /// across borders into flowing loops.
        case arcs
        /// One corner-to-corner diagonal (`╲` or `╱`): a maze of corridors.
        case diagonals
    }

    /// The line-work of a Truchet tiling over `grid`, one tile per cell, each
    /// spun to a random orientation drawn from `rng`. Returns open `Contour`s:
    /// two quarter-arcs per cell for `.arcs`, one diagonal per cell for
    /// `.diagonals`.
    public static func contours<R: RandomNumberGenerator>(
        grid: Grid,
        tile: Tile = .arcs,
        using rng: inout R
    ) -> [Contour] {
        var out: [Contour] = []
        out.reserveCapacity(grid.columns * grid.rows * (tile == .arcs ? 2 : 1))
        for cell in grid.cells {
            let flipped = Bool.random(using: &rng)
            out.append(contentsOf: contours(in: cell.frame, tile: tile, flipped: flipped))
        }
        return out
    }

    /// The line-work of a single tile laid in `rect` at a *chosen* spin: the
    /// two quarter-arcs of `.arcs`, or the one diagonal of `.diagonals`
    /// (`flipped: false` is `╲`, `true` is `╱`). The grid form above places
    /// these per cell with seeded spins; this form is for hand-authoring a
    /// tiling one tile at a time (a weighted layout, a hover preview, a
    /// diagram of the tile itself).
    public static func contours(in rect: Rectangle, tile: Tile = .arcs,
                                flipped: Bool = false) -> [Contour] {
        switch tile {
        case .arcs:
            return arcContours(in: rect, flipped: flipped)
        case .diagonals:
            return [diagonalContour(in: rect, flipped: flipped)]
        }
    }

    // MARK: - Tile geometry

    /// How finely each quarter-arc is flattened into a polyline.
    private static let arcSegments = 16

    /// The two quarter-arcs of an `.arcs` tile. Each arc is centered on a cell
    /// corner and passes through the midpoints of the two edges meeting there, so
    /// abutting cells' arcs join at the shared edge midpoint regardless of how
    /// either was flipped. `flipped` swaps which diagonal pair of corners the arcs
    /// hug.
    private static func arcContours(in r: Rectangle, flipped: Bool) -> [Contour] {
        let rx = r.width / 2, ry = r.height / 2
        let tl = r.topLeft, tr = r.topRight, bl = r.bottomLeft, br = r.bottomRight
        let halfPi = Double.pi / 2
        if !flipped {
            return [
                Contour(quarterArc(center: tl, rx: rx, ry: ry, from: 0, to: halfPi), closed: false),
                Contour(quarterArc(center: br, rx: rx, ry: ry, from: .pi, to: .pi + halfPi), closed: false),
            ]
        } else {
            return [
                Contour(quarterArc(center: tr, rx: rx, ry: ry, from: halfPi, to: .pi), closed: false),
                Contour(quarterArc(center: bl, rx: rx, ry: ry, from: .pi + halfPi, to: 2 * .pi), closed: false),
            ]
        }
    }

    /// A quarter of an ellipse centered on `center` with radii `rx`/`ry`, sampled
    /// from angle `from` to `to` (y-down, so a positive angle sweeps downward).
    private static func quarterArc(center: Vector2, rx: Double, ry: Double,
                                   from: Double, to: Double) -> [Vector2] {
        (0...arcSegments).map { i in
            let angle = from + (to - from) * Double(i) / Double(arcSegments)
            return Vector2(center.x + rx * cos(angle), center.y + ry * sin(angle))
        }
    }

    /// The single diagonal of a `.diagonals` tile: `╲` (top-left to bottom-right)
    /// or, when `flipped`, `╱` (top-right to bottom-left).
    private static func diagonalContour(in r: Rectangle, flipped: Bool) -> Contour {
        let points = flipped ? [r.topRight, r.bottomLeft] : [r.topLeft, r.bottomRight]
        return Contour(points, closed: false)
    }
}

// MARK: - Sketch sugar

public extension Sketch {
    /// The line-work of a Truchet tiling over a `columns × rows` grid of `bounds`
    /// (the whole canvas by default), one tile per cell spun to a random
    /// orientation. Driven by the seeded `random`, so `seed(_:)` makes the layout
    /// reproducible. Returns open `Contour`s you stroke (or feed to the booleans,
    /// hatching, or SVG export); for the plain case, `drawTruchet` strokes them
    /// for you.
    ///
    /// ```swift
    /// seed(3)
    /// stroke(.white); strokeWeight(8); strokeCap(.round)
    /// for c in truchet(columns: 12, rows: 12, tile: .arcs) {
    ///     drawPolyline(c.points)   // color each one for flowing waves
    /// }
    /// ```
    func truchet(in bounds: Rectangle? = nil, columns: Int, rows: Int,
                 tile: Truchet.Tile = .arcs) -> [Contour] {
        let grid = Grid(in: bounds ?? self.bounds, columns: columns, rows: rows)
        return Truchet.contours(grid: grid, tile: tile, using: &rng)
    }

    /// Draw a Truchet tiling over a `columns × rows` grid of `bounds` (the canvas
    /// by default) with the current `stroke`. For per-tile color, iterate the
    /// `truchet(…)` value's contours instead.
    func drawTruchet(in bounds: Rectangle? = nil, columns: Int, rows: Int,
                     tile: Truchet.Tile = .arcs) {
        for contour in truchet(in: bounds, columns: columns, rows: rows, tile: tile) {
            drawPolyline(contour.points, closed: false)
        }
    }
}
