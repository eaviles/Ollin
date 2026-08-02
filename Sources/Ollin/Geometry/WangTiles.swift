import Foundation

/// One Wang tile: a square with a color on each edge. Tiles are placed
/// unrotated, and two tiles may sit side by side only where the touching
/// edges carry the same color. Colors are plain integers; what they *look*
/// like is up to the drawing (edge triangles, connecting roads, texture
/// patches).
public struct WangTile: Sendable, Equatable {
    public let top: Int
    public let right: Int
    public let bottom: Int
    public let left: Int

    /// Relative likelihood when several tiles fit the same slot.
    public let weight: Double

    public init(top: Int, right: Int, bottom: Int, left: Int, weight: Double = 1) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
        self.weight = max(0, weight)
    }
}

/// A grid filled with Wang tiles so that every touching edge matches. Wang
/// tiles are where aperiodicity was first found (a set of squares that tile
/// the plane but never periodically); in creative coding the same idea runs
/// the other way, as a seeded scanline fill over a small tile set whose edge
/// constraints turn independent random picks into one connected pattern.
///
/// The scanline fill picks each cell's tile among those matching the colors
/// already fixed by its west and north neighbors (weighted by `weight`). With
/// a *complete* set (`WangTiling.completeSet`), some tile fits every
/// combination, so the fill always succeeds; hand-built sets that can dead-end
/// get fresh attempts, and `nil` means none succeeded.
///
/// ```swift
/// let tiling = wangTiling(WangTiling.completeSet(colors: 2), columns: 12, rows: 12)
/// ```
public struct WangTiling: Sendable, Equatable {
    /// The tile set the grid was filled from.
    public let tiles: [WangTile]
    public let columns: Int
    public let rows: Int

    /// Row-major indices into `tiles`, one per cell.
    public let indices: [Int]

    /// The chosen tile index at a cell.
    public func tileIndex(column: Int, row: Int) -> Int {
        indices[row * columns + column]
    }

    /// The chosen tile at a cell.
    public func tile(column: Int, row: Int) -> WangTile {
        tiles[tileIndex(column: column, row: row)]
    }

    /// Every tile with every edge-color combination drawn from `colors`
    /// colors: the guaranteed-to-fill set (`colors^4` tiles). Two colors give
    /// the classic 16-tile set.
    public static func completeSet(colors: Int) -> [WangTile] {
        let n = max(1, colors)
        var tiles: [WangTile] = []
        tiles.reserveCapacity(n * n * n * n)
        for top in 0..<n {
            for right in 0..<n {
                for bottom in 0..<n {
                    for left in 0..<n {
                        tiles.append(WangTile(top: top, right: right, bottom: bottom, left: left))
                    }
                }
            }
        }
        return tiles
    }

    /// Fill a `columns x rows` grid from `tiles` in scanline order, matching
    /// west and north constraints, drawing choices from `rng`. Returns `nil`
    /// when every attempt dead-ends (impossible with a complete set).
    public static func fill<R: RandomNumberGenerator>(
        tiles: [WangTile],
        columns: Int,
        rows: Int,
        attempts: Int = 20,
        using rng: inout R
    ) -> WangTiling? {
        guard columns > 0, rows > 0, !tiles.isEmpty else { return nil }

        for _ in 0..<max(1, attempts) {
            var indices: [Int] = []
            indices.reserveCapacity(columns * rows)
            var stuck = false

            for row in 0..<rows {
                for column in 0..<columns {
                    let west = column > 0 ? tiles[indices[row * columns + column - 1]].right : nil
                    let north = row > 0 ? tiles[indices[(row - 1) * columns + column]].bottom : nil
                    var candidates: [Int] = []
                    var totalWeight = 0.0
                    for (i, tile) in tiles.enumerated() {
                        if let west, tile.left != west { continue }
                        if let north, tile.top != north { continue }
                        if tile.weight <= 0 { continue }
                        candidates.append(i)
                        totalWeight += tile.weight
                    }
                    guard !candidates.isEmpty else { stuck = true; break }

                    var pick = Double.random(in: 0..<totalWeight, using: &rng)
                    var chosen = candidates[candidates.count - 1]
                    for i in candidates {
                        pick -= tiles[i].weight
                        if pick < 0 { chosen = i; break }
                    }
                    indices.append(chosen)
                }
                if stuck { break }
            }

            if !stuck {
                return WangTiling(tiles: tiles, columns: columns, rows: rows, indices: indices)
            }
        }
        return nil
    }
}

// MARK: - Sketch sugar

public extension Sketch {
    /// Fill a `columns x rows` grid with Wang tiles from `tiles`, matching
    /// every touching edge, driven by the seeded `random` (so `seed(_:)`
    /// reproduces the layout). Returns `nil` only for a tile set that
    /// dead-ends on every attempt; `WangTiling.completeSet` never does.
    ///
    /// ```swift
    /// if let tiling = wangTiling(WangTiling.completeSet(colors: 2),
    ///                            columns: 12, rows: 12) {
    ///     // draw each cell from tiling.tile(column:row:)
    /// }
    /// ```
    func wangTiling(_ tiles: [WangTile], columns: Int, rows: Int,
                    attempts: Int = 20) -> WangTiling? {
        WangTiling.fill(tiles: tiles, columns: columns, rows: rows,
                        attempts: attempts, using: &rng)
    }

    /// Draw a Wang tiling into `bounds` (the whole canvas by default) in the
    /// classic style: each cell split into four triangles meeting at the
    /// center, each triangle filled with its edge's color from `colors`
    /// (indexed by edge color id, wrapping if short).
    func drawWangTiling(_ tiling: WangTiling, colors: [Color], in bounds: Rectangle? = nil) {
        guard !colors.isEmpty else { return }
        let grid = Grid(in: bounds ?? canvasRectangle,
                        columns: tiling.columns, rows: tiling.rows)
        withState {
            for cell in grid.cells {
                let tile = tiling.tile(column: cell.column, row: cell.row)
                let f = cell.frame
                let c = f.center
                let corners = [f.topLeft, f.topRight, f.bottomRight, f.bottomLeft]
                let edgeColors = [tile.top, tile.right, tile.bottom, tile.left]
                for i in 0..<4 {
                    fill(colors[edgeColors[i] % colors.count])
                    drawPolygon([corners[i], corners[(i + 1) % 4], c])
                }
            }
        }
    }
}
