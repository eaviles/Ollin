import Foundation

/// The maze of diagonals: fill a grid with cells, and in each one draw one of two
/// diagonals by a coin flip. The diagonals meet at the cells' corners, so what
/// comes out is not a field of loose marks but a single tangle of long connected
/// paths, and it never repeats.
///
/// It is the picture a famous one-line program printed forever on an early home
/// computer, and about the smallest amount of code anyone has needed to make
/// something worth looking at: two characters, a coin, and a grid.
///
/// ```swift
/// seed(5)
/// let maze = tenPrint(columns: 40, rows: 40)
/// stroke(.white); strokeWeight(6); strokeCap(.round)
/// for run in maze.runs { drawPolyline(run.points) }
/// ```
///
/// Two faces come out of one design:
///
/// - `lines` is the plain reading, one two-point `Contour` per cell, which is what
///   the original printed.
/// - `runs` joins those diagonals end to end wherever they meet, so a pen travels
///   a long way before it lifts. That is the one to stroke and the one to plot.
public struct TenPrint: Equatable, Sendable {
    /// The grid the diagonals are drawn in. Its `gutter` does not apply: a
    /// diagonal runs corner to corner of its cell, so neighbors meet.
    public let grid: Grid
    /// One bit per cell, row-major, so it zips with `grid.cells`. `false` is the
    /// forward diagonal (bottom-left to top-right), `true` the back one
    /// (top-left to bottom-right). A shorter array repeats, so a small motif
    /// tiles a large field; an empty one reads as all `false`.
    public let bits: [Bool]

    /// A design from explicit bits, for a hand-authored or encoded pattern.
    public init(grid: Grid, bits: [Bool]) {
        self.grid = grid
        self.bits = bits
    }

    /// A design whose bits come from `rng`, each `true` with `probability`. At
    /// `0.5` the balanced tangle; pushed toward 0 or 1 the field combs into long
    /// parallel diagonals with the odd cell crossing them.
    public init<R: RandomNumberGenerator>(grid: Grid, probability: Double = 0.5,
                                          using rng: inout R) {
        let p = Swift.min(Swift.max(probability, 0), 1)
        self.grid = grid
        self.bits = (0 ..< Swift.max(0, grid.columns * grid.rows)).map { _ in
            Double.random(in: 0 ..< 1, using: &rng) < p
        }
    }

    // MARK: - The two faces

    /// The bit for a cell, with a shorter `bits` array repeating.
    public func bit(column: Int, row: Int) -> Bool {
        guard !bits.isEmpty else { return false }
        let index = row * grid.columns + column
        return bits[((index % bits.count) + bits.count) % bits.count]
    }

    /// One open two-point `Contour` per cell: the diagonal that cell drew.
    public var lines: [Contour] {
        (0 ..< grid.rows).flatMap { row in
            (0 ..< grid.columns).map { column in
                let ends = corners(column: column, row: row)
                return Contour([ends.0, ends.1], closed: false)
            }
        }
    }

    /// The same diagonals, joined end to end wherever they meet at a corner.
    ///
    /// A corner where an odd number of diagonals meet has to be the end of some
    /// path, so every walk starts at a corner that is odd *right now*, which is
    /// what keeps the count near the fewest possible. Whatever the walks leave
    /// behind is loops, taken from anywhere. It is not proven to be the shortest
    /// set of paths: that would need the leftovers spliced back into the paths
    /// running through them, which is more machinery than a pen lift is worth.
    public var runs: [Contour] {
        let columns = grid.columns, rows = grid.rows
        guard columns > 0, rows > 0 else { return [] }
        let across = columns + 1

        // One edge per cell, between two corners of the grid's lattice.
        var ends: [(Int, Int)] = []
        ends.reserveCapacity(columns * rows)
        for row in 0 ..< rows {
            for column in 0 ..< columns {
                let back = bit(column: column, row: row)
                let a = back ? row * across + column : (row + 1) * across + column
                let b = back ? (row + 1) * across + column + 1 : row * across + column + 1
                ends.append((a, b))
            }
        }

        // Which edges touch each corner.
        var touching = [[Int]](repeating: [], count: across * (rows + 1))
        for (edge, pair) in ends.enumerated() {
            touching[pair.0].append(edge)
            touching[pair.1].append(edge)
        }
        var degree = touching.map(\.count)
        var used = [Bool](repeating: false, count: ends.count)

        func walk(from start: Int) -> Contour {
            var corner = start
            var points = [position(ofCorner: corner)]
            while true {
                guard let edge = touching[corner].first(where: { !used[$0] }) else { break }
                used[edge] = true
                let next = ends[edge].0 == corner ? ends[edge].1 : ends[edge].0
                degree[corner] -= 1
                degree[next] -= 1
                points.append(position(ofCorner: next))
                corner = next
            }
            return Contour(points, closed: false)
        }

        var paths: [Contour] = []
        // Every corner that is odd right now has to end a path, so start there.
        var corner = 0
        while corner < degree.count {
            if degree[corner] % 2 == 1 {
                paths.append(walk(from: corner))
                // The walk may have left this corner odd again, so look again.
                continue
            }
            corner += 1
        }
        // Whatever is left is loops.
        for corner in 0 ..< degree.count where degree[corner] > 0 {
            while degree[corner] > 0 { paths.append(walk(from: corner)) }
        }
        return paths.filter { $0.points.count > 1 }
    }

    // MARK: - Where a cell's diagonal ends

    /// A corner of the lattice the cells sit on. Worked out from the bounds
    /// rather than a cell's frame, so the `gutter` never opens a gap that would
    /// stop two diagonals meeting.
    private func latticePoint(column: Int, row: Int) -> Vector2 {
        let columns = Double(Swift.max(grid.columns, 1))
        let rows = Double(Swift.max(grid.rows, 1))
        return Vector2(grid.bounds.x + Double(column) * grid.bounds.width / columns,
                       grid.bounds.y + Double(row) * grid.bounds.height / rows)
    }

    private func corners(column: Int, row: Int) -> (Vector2, Vector2) {
        bit(column: column, row: row)
            ? (latticePoint(column: column, row: row),
               latticePoint(column: column + 1, row: row + 1))
            : (latticePoint(column: column, row: row + 1),
               latticePoint(column: column + 1, row: row))
    }

    private func position(ofCorner index: Int) -> Vector2 {
        let across = grid.columns + 1
        return latticePoint(column: index % across, row: index / across)
    }
}

public extension Sketch {
    /// A maze of diagonals over a `columns × rows` grid of `bounds` (the whole
    /// canvas by default), each cell's coin flipped by the seeded `random`, so
    /// `seed(_:)` makes the design reproducible.
    ///
    /// ```swift
    /// seed(5)
    /// let maze = tenPrint(columns: 40, rows: 40)
    /// stroke(.white); strokeWeight(6); strokeCap(.round)
    /// for run in maze.runs { drawPolyline(run.points) }
    /// ```
    func tenPrint(in bounds: Rectangle? = nil, columns: Int, rows: Int,
                  probability: Double = 0.5) -> TenPrint {
        let grid = Grid(in: bounds ?? self.bounds, columns: columns, rows: rows)
        return TenPrint(grid: grid, probability: probability, using: &rng)
    }

    /// Draw a maze of diagonals with the current `stroke`, as joined runs. For the
    /// per-cell reading or per-path color, hold the `tenPrint(…)` value and draw
    /// its faces yourself.
    func drawTenPrint(in bounds: Rectangle? = nil, columns: Int, rows: Int,
                      probability: Double = 0.5) {
        for run in tenPrint(in: bounds, columns: columns, rows: rows,
                            probability: probability).runs {
            drawPolyline(run.points)
        }
    }
}
