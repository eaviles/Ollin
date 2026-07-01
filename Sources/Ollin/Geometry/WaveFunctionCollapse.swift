import Foundation

/// A tile for [`WaveFunctionCollapse`](x-source-tag://WaveFunctionCollapse): four
/// edge *sockets* and a relative `weight`. Two tiles may sit next to each other
/// when the sockets on their shared edge are equal, so a socket is just a label
/// (an `Int`) for what an edge connects to. A higher `weight` makes a tile more
/// likely to be chosen when a cell collapses.
///
/// Sockets are listed clockwise from the top: `[top, right, bottom, left]`. Use
/// `rotations()` to generate a tile's rotated variants (with the sockets rotated
/// to match) instead of writing each by hand.
public struct WFCTile: Sendable, Equatable {
    /// The four edge sockets, clockwise from the top: `[top, right, bottom, left]`.
    public let sockets: [Int]
    /// How likely this tile is when a cell collapses (relative to the others).
    public let weight: Double

    /// A tile from its four edge sockets (`[top, right, bottom, left]`) and an
    /// optional weight.
    public init(_ sockets: [Int], weight: Double = 1) {
        precondition(sockets.count == 4, "A WFCTile needs exactly four sockets: [top, right, bottom, left]")
        self.sockets = sockets
        self.weight = weight
    }

    /// The same tile turned 90° clockwise, with its sockets rotated to match.
    public func rotated() -> WFCTile {
        WFCTile([sockets[3], sockets[0], sockets[1], sockets[2]], weight: weight)
    }

    /// This tile and its rotations (up to four, turning 90° each time). Handy for
    /// building a tileset from one drawn tile per shape.
    public func rotations(_ count: Int = 4) -> [WFCTile] {
        var out: [WFCTile] = []
        var t = self
        for _ in 0 ..< Swift.max(Swift.min(count, 4), 1) {
            out.append(t)
            t = t.rotated()
        }
        return out
    }
}

/// Wave Function Collapse: fill a grid from a small set of tiles so that every
/// pair of neighbors is legal. Each cell starts holding *all* tiles at once; the
/// solver repeatedly collapses the most-constrained cell to a single tile (a
/// weighted random pick) and propagates that choice to its neighbors, until every
/// cell is decided. It's the constraint-solving, texture-synthesis technique
/// behind procedurally-generated tile maps.
///
/// The result is a grid of tile indices (into your `tiles`), which you draw
/// however you like: each tile is a `Shape` or a small draw block, so it feeds
/// the existing geometry path. A run is a pure function of the seed, so the same
/// seed always solves the same layout.
///
/// ```swift
/// // A pipe network: a blank tile plus connectors, with their rotations.
/// let blank = WFCTile([0, 0, 0, 0])
/// let line  = WFCTile([1, 0, 1, 0]).rotations(2)   // vertical + horizontal
/// let elbow = WFCTile([1, 1, 0, 0]).rotations()    // four corners
/// let tiles = [blank] + line + elbow
///
/// if let grid = wfc(tiles: tiles, columns: 16, rows: 16) {
///     drawWFC(grid) { i, cell in
///         // draw a line from the cell center to each connected edge
///         drawConnections(tiles[i].sockets, in: cell)
///     }
/// }
/// ```
///
/// - Tag: WaveFunctionCollapse
public struct WaveFunctionCollapse: Sendable {
    /// The tileset the grid is filled from.
    public let tiles: [WFCTile]
    /// The grid width in cells.
    public let columns: Int
    /// The grid height in cells.
    public let rows: Int

    /// A solver over `tiles` for a `columns × rows` grid.
    public init(tiles: [WFCTile], columns: Int, rows: Int) {
        self.tiles = tiles
        self.columns = columns
        self.rows = rows
    }

    /// Solve the grid, returning a `columns × rows` array of tile indices
    /// (`grid[column][row]`), or `nil` if no legal filling was found within
    /// `attempts` restarts. A contradiction (a cell left with no legal tile)
    /// restarts the whole solve, drawing fresh choices from `rng`.
    public func solve<R: RandomNumberGenerator>(attempts: Int = 40, using rng: inout R) -> [[Int]]? {
        let n = tiles.count
        guard n > 0, columns > 0, rows > 0 else { return nil }

        // adjacency[d][t] = the tiles allowed in the neighbor to direction d
        // (0 = up, 1 = right, 2 = down, 3 = left) of a cell holding tile t,
        // i.e. the sockets on the shared edge match.
        var adjacency = Array(repeating: Array(repeating: Set<Int>(), count: n), count: 4)
        for t in 0 ..< n {
            for s in 0 ..< n {
                if tiles[t].sockets[0] == tiles[s].sockets[2] { adjacency[0][t].insert(s) }   // up
                if tiles[t].sockets[1] == tiles[s].sockets[3] { adjacency[1][t].insert(s) }   // right
                if tiles[t].sockets[2] == tiles[s].sockets[0] { adjacency[2][t].insert(s) }   // down
                if tiles[t].sockets[3] == tiles[s].sockets[1] { adjacency[3][t].insert(s) }   // left
            }
        }

        for _ in 0 ..< Swift.max(attempts, 1) {
            if let grid = attempt(adjacency: adjacency, tileCount: n, using: &rng) {
                return grid
            }
        }
        return nil
    }

    // MARK: - One solve attempt

    // Neighbor offsets for directions 0…3 (up, right, down, left).
    private static let offsets: [(dx: Int, dy: Int)] = [(0, -1), (1, 0), (0, 1), (-1, 0)]

    private func attempt<R: RandomNumberGenerator>(adjacency: [[Set<Int>]], tileCount n: Int,
                                                   using rng: inout R) -> [[Int]]? {
        // Every cell starts in a superposition of all tiles.
        let all = Set(0 ..< n)
        var wave = Array(repeating: Array(repeating: all, count: rows), count: columns)

        var remaining = columns * rows
        while remaining > 0 {
            guard let (c, r) = lowestEntropyCell(wave, using: &rng) else { break }
            collapse(&wave[c][r], using: &rng)
            remaining -= 1
            if !propagate(&wave, from: (c, r), adjacency: adjacency) { return nil }
            // Propagation may have collapsed other cells; recount by scanning is
            // O(cells) but simplest, and cells only ever shrink, so count the ones
            // still undecided.
            remaining = countUndecided(wave)
        }

        // Extract the single tile in each cell.
        var grid = Array(repeating: Array(repeating: 0, count: rows), count: columns)
        for c in 0 ..< columns {
            for r in 0 ..< rows {
                guard let only = wave[c][r].first, wave[c][r].count == 1 else { return nil }
                grid[c][r] = only
            }
        }
        return grid
    }

    /// The undecided cell (more than one possibility) with the fewest options,
    /// with a small random noise to break ties. `nil` when all cells are decided.
    private func lowestEntropyCell<R: RandomNumberGenerator>(_ wave: [[Set<Int>]],
                                                             using rng: inout R) -> (Int, Int)? {
        var best: (Int, Int)? = nil
        var bestKey = Double.infinity
        for c in 0 ..< columns {
            for r in 0 ..< rows {
                let count = wave[c][r].count
                guard count > 1 else { continue }
                // Draw noise in a fixed cell order so the choice is reproducible.
                let key = Double(count) + Double.random(in: 0 ..< 0.5, using: &rng)
                if key < bestKey { bestKey = key; best = (c, r) }
            }
        }
        return best
    }

    /// Collapse a cell to one tile, chosen at random weighted by tile weight.
    private func collapse<R: RandomNumberGenerator>(_ cell: inout Set<Int>, using rng: inout R) {
        // Sort so the weighted pick is deterministic (Set order is randomized).
        let candidates = cell.sorted()
        let total = candidates.reduce(0.0) { $0 + tiles[$1].weight }
        var pick = Double.random(in: 0 ..< Swift.max(total, .leastNonzeroMagnitude), using: &rng)
        var chosen = candidates[0]
        for t in candidates {
            pick -= tiles[t].weight
            if pick < 0 { chosen = t; break }
        }
        cell = [chosen]
    }

    /// Arc-consistency propagation: shrink neighbors to only the tiles that some
    /// remaining tile in the current cell allows, spreading outward until stable.
    /// Returns `false` on a contradiction (a neighbor emptied).
    private func propagate(_ wave: inout [[Set<Int>]], from start: (Int, Int),
                           adjacency: [[Set<Int>]]) -> Bool {
        var stack = [start]
        while let (c, r) = stack.popLast() {
            for d in 0 ..< 4 {
                let nc = c + Self.offsets[d].dx, nr = r + Self.offsets[d].dy
                guard nc >= 0, nc < columns, nr >= 0, nr < rows else { continue }
                // The tiles the neighbor may still hold: the union of what each
                // tile still possible here permits in direction d.
                var allowed = Set<Int>()
                for t in wave[c][r] { allowed.formUnion(adjacency[d][t]) }
                let before = wave[nc][nr].count
                wave[nc][nr].formIntersection(allowed)
                let after = wave[nc][nr].count
                if after == 0 { return false }
                if after < before { stack.append((nc, nr)) }
            }
        }
        return true
    }

    private func countUndecided(_ wave: [[Set<Int>]]) -> Int {
        var count = 0
        for c in 0 ..< columns { for r in 0 ..< rows where wave[c][r].count > 1 { count += 1 } }
        return count
    }
}

// MARK: - Sketch sugar

public extension Sketch {
    /// Solve a Wave Function Collapse over `tiles` for a `columns × rows` grid,
    /// returning the `grid[column][row]` tile indices (or `nil` if unsolved after
    /// `attempts` restarts). Driven by the seeded `random`, so `seed(_:)` makes
    /// the layout reproducible. Solving is not cheap, so do it once (in `setup`
    /// or a stored property) rather than every frame, then draw the result with
    /// `drawWFC`.
    ///
    /// ```swift
    /// let grid = wfc(tiles: tiles, columns: 16, rows: 16)
    /// ```
    func wfc(tiles: [WFCTile], columns: Int, rows: Int, attempts: Int = 40) -> [[Int]]? {
        WaveFunctionCollapse(tiles: tiles, columns: columns, rows: rows)
            .solve(attempts: attempts, using: &rng)
    }

    /// Draw a solved WFC `grid` by laying a `Grid` over `bounds` (the canvas by
    /// default) and calling `tile` for each cell with its tile index and frame.
    /// The grid's dimensions are read from `grid` itself.
    ///
    /// ```swift
    /// drawWFC(grid) { index, cell in
    ///     // draw tile `index` inside the `cell` rectangle
    /// }
    /// ```
    func drawWFC(_ grid: [[Int]], in bounds: Rectangle? = nil,
                 padding: Insets = 0, gutter: Double = 0,
                 tile: (Int, Rectangle) -> Void) {
        let columns = grid.count
        guard columns > 0 else { return }
        let rows = grid[0].count
        guard rows > 0 else { return }
        let layout = Grid(in: bounds ?? self.bounds, columns: columns, rows: rows,
                          padding: padding, gutter: gutter)
        for cell in layout.cells {
            tile(grid[cell.column][cell.row], cell.frame)
        }
    }
}
