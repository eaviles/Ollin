import Foundation

/// A spatial index over a set of 2D points: the structure that answers "what is
/// near here" without comparing against every point.
///
/// A sketch reaches for one whenever a loop over points hides a second loop over
/// points. Stipple relaxation, flocking, packing, growth, hit testing under the
/// mouse: all of them ask the same three questions, and all of them cost
/// `count * count` comparisons when asked directly.
///
/// ```swift
/// let index = SpatialIndex(points)
/// if let i = index.nearest(to: mouse) { drawCircle(points[i], 8) }
/// for j in index.neighbors(of: mouse, within: 60) { drawLine(mouse, points[j]) }
/// ```
///
/// Every query answers with **indices into `points`**, so a sketch keeps its own
/// payload beside the positions and reads it back with the same index.
///
/// ## The two kinds
///
/// - ``Kind/grid`` (the default) sorts the points into square cells and reads the
///   block of cells a query reaches. It is the right choice when the points are
///   spread over the area at a similar density, which covers nearly every sketch,
///   and it is the only kind that takes new points cheaply after it is built.
/// - ``Kind/tree`` splits the set in half, then each half in half again, along
///   whichever axis is widest. It stays fast when the points are gathered into
///   tight clumps with wide empty space between them, where a grid has to walk
///   many empty cells to reach them.
///
/// The kind is a speed choice and never a correctness one: every query that
/// answers with an array answers identically, down to the order. The two forms
/// that hand back one point at a time (``forEachNeighbor(of:within:_:)`` and
/// ``anyNeighbor(of:within:)``) each walk in their own kind's fixed order, which
/// reproduces from run to run but is not the same between the kinds.
///
/// ## Reproducibility
///
/// A query returns its indices in a fixed order (ascending distance and then
/// ascending index, or ascending index for the region and neighbor lists), and
/// ties break toward the lower index. Two runs over the same points always agree,
/// which is what keeps a seeded sketch reproducible.
public struct SpatialIndex: Sendable {

    /// How an index arranges its points. Both kinds answer the same queries with
    /// the same results; they differ in what they are fast at.
    public enum Kind: Sendable, Hashable {
        /// Square cells of a fixed size. Fast for evenly spread points, and the
        /// kind that accepts new points after the build.
        case grid
        /// A k-d tree: repeated halving along the widest axis. Fast for clumped
        /// points, and rebuilt when new points arrive.
        case tree
    }

    /// The points the index was built over, in the order they were given.
    /// A point added later sits at the end, at the index ``insert(_:)`` returned.
    public private(set) var points: [Vector2]

    /// Which arrangement this index uses.
    public let kind: Kind

    private var grid: CellGrid
    private var tree: KDTree2?

    // MARK: - Building

    /// An index over `points`.
    ///
    /// With no `cellSize`, a grid sizes its cells so that a cell holds about one
    /// point, which is the size that balances the walk against the number of
    /// cells. Pass the radius you plan to query with when you know it: a cell
    /// equal to that radius reads a 3 by 3 block and nothing more.
    public init(_ points: [Vector2], kind: Kind = .grid, cellSize: Double? = nil) {
        self.points = points
        self.kind = kind
        self.grid = CellGrid(points: points, cellSize: cellSize)
        self.tree = kind == .tree ? KDTree2(points: points) : nil
    }

    /// An empty index ready to take points inside `bounds`, for the sketches that
    /// grow a set rather than start with one (dart throwing, aggregation, a mark
    /// dropped where the mouse goes).
    ///
    /// A point that lands outside `bounds` is still indexed correctly; the box
    /// simply grows to take it.
    public init(bounds: Rectangle, cellSize: Double, kind: Kind = .grid) {
        self.points = []
        self.kind = kind
        self.grid = CellGrid(bounds: bounds, cellSize: cellSize)
        self.tree = kind == .tree ? KDTree2(points: []) : nil
    }

    /// How many points the index holds.
    public var count: Int { points.count }

    /// Whether the index holds no points.
    public var isEmpty: Bool { points.isEmpty }

    /// The edge length of a grid cell. A tree kind reports the size its grid
    /// would use.
    public var cellSize: Double { grid.cellSize }

    /// Add a point and answer with its index.
    ///
    /// A grid takes the point in place. A tree rebuilds, which costs
    /// `count * log(count)`, so build a tree from a finished set and grow a grid.
    @discardableResult
    public mutating func insert(_ point: Vector2) -> Int {
        let index = points.count
        points.append(point)
        grid.insert(point)
        if kind == .tree { tree = KDTree2(points: points) }
        return index
    }

    // MARK: - Queries

    /// The index of the point nearest to `p`, or nil when the index is empty.
    /// Equal distances answer with the lower index.
    public func nearest(to p: Vector2) -> Int? {
        guard !points.isEmpty else { return nil }
        if let tree { return tree.nearest(to: p) }
        return grid.nearest(to: p)
    }

    /// The indices of the `k` points nearest to `p`, ascending by distance and
    /// then by index. Fewer come back only when the set is smaller than `k`.
    public func kNearest(_ k: Int, to p: Vector2) -> [Int] {
        guard k > 0, !points.isEmpty else { return [] }
        let want = Swift.min(k, points.count)
        if let tree { return tree.kNearest(want, to: p) }
        return grid.kNearest(want, to: p)
    }

    /// The indices of every point within `radius` of `p`, ascending by index.
    /// The boundary counts as inside.
    public func neighbors(of p: Vector2, within radius: Double) -> [Int] {
        var found: [Int] = []
        forEachNeighbor(of: p, within: radius) { index, _ in found.append(index) }
        found.sort()
        return found
    }

    /// The indices of every point within `radius` of the point at `index`,
    /// ascending by index, leaving out that point itself. This is the flocking
    /// and relaxation form, where each point asks about the others.
    public func neighbors(of index: Int, within radius: Double) -> [Int] {
        var found: [Int] = []
        forEachNeighbor(of: index, within: radius) { other, _ in found.append(other) }
        found.sort()
        return found
    }

    /// Visit every point within `radius` of `p` without building an array.
    /// `body` receives the point's index and its **squared** distance to `p`.
    ///
    /// This is the form to call in a loop that already runs per point per frame:
    /// it allocates nothing, and the squared distance is the number the caller
    /// usually wants anyway.
    public func forEachNeighbor(of p: Vector2, within radius: Double,
                             _ body: (Int, Double) -> Void) {
        guard !points.isEmpty, radius > 0 else { return }
        if let tree { tree.forEachNeighbor(of: p, within: radius, skipping: -1, body) }
        else { grid.forEachNeighbor(of: p, within: radius, skipping: -1, body) }
    }

    /// Visit every point within `radius` of the point at `index`, leaving out
    /// that point itself.
    public func forEachNeighbor(of index: Int, within radius: Double,
                             _ body: (Int, Double) -> Void) {
        guard points.indices.contains(index), radius > 0 else { return }
        let p = points[index]
        if let tree { tree.forEachNeighbor(of: p, within: radius, skipping: index, body) }
        else { grid.forEachNeighbor(of: p, within: radius, skipping: index, body) }
    }

    /// The first point found within `radius` of `p`, or nil when there is none.
    ///
    /// The answer is "one of the near ones", picked in the index's own fixed walk
    /// order, so it reproduces. Use it for the yes-or-no question ("is anything
    /// too close to drop a point here?"), which is what dart throwing and
    /// aggregation ask, and where finding *all* the neighbors is wasted work.
    public func anyNeighbor(of p: Vector2, within radius: Double) -> Int? {
        guard !points.isEmpty, radius > 0 else { return nil }
        if let tree { return tree.anyNeighbor(of: p, within: radius, skipping: -1) }
        return grid.anyNeighbor(of: p, within: radius, skipping: -1)
    }

    /// Whether any point lies within `radius` of `p`.
    public func hasNeighbor(of p: Vector2, within radius: Double) -> Bool {
        anyNeighbor(of: p, within: radius) != nil
    }

    /// The indices of every point inside `region`, ascending by index. The
    /// boundary counts as inside, matching `Rectangle.contains(_:)`.
    public func indices(in region: Rectangle) -> [Int] {
        guard !points.isEmpty else { return [] }
        var found: [Int] = []
        if let tree { tree.forPoints(in: region) { found.append($0) } }
        else { grid.forPoints(in: region) { found.append($0) } }
        found.sort()
        return found
    }
}

// MARK: - The grid backing

/// A uniform grid of square cells over a growing set of 2D points, kept as flat
/// coordinate arrays plus one list of point indices per cell.
///
/// One list per cell rather than one sorted run per cell is what lets a point be
/// added in place, which is half of what a sketch does with a point set (dart
/// throwing, aggregation, a mark dropped where the mouse goes).
///
/// The coordinates are held apart from the `Vector2` array on purpose. This walk
/// runs per point per frame in sketches that are built in debug, where every
/// non-transparent operation costs a real function call, and the flat arrays are
/// what keep the inner loop to plain arithmetic.
struct CellGrid {

    private(set) var cellSize: Double
    private var minX: Double, minY: Double
    private var nx: Int, ny: Int
    /// Point indices per cell, column-major (`column * ny + row`), each cell
    /// ascending by index because points arrive in index order.
    private var cells: [[Int32]]
    private var xs: [Double], ys: [Double]

    // MARK: Building

    init(points: [Vector2], cellSize explicit: Double?) {
        var loX = Double.infinity, loY = Double.infinity
        var hiX = -Double.infinity, hiY = -Double.infinity
        for p in points {
            if p.x < loX { loX = p.x }; if p.x > hiX { hiX = p.x }
            if p.y < loY { loY = p.y }; if p.y > hiY { hiY = p.y }
        }
        if points.isEmpty { loX = 0; loY = 0; hiX = 0; hiY = 0 }

        let width = hiX - loX, height = hiY - loY
        let size = explicit ?? CellGrid.automaticCellSize(width, height, points.count)
        let fitted = CellGrid.fit(width, height, size, points.count)
        cellSize = fitted.size; nx = fitted.nx; ny = fitted.ny
        minX = CellGrid.snapped(loX, cellSize); minY = CellGrid.snapped(loY, cellSize)
        cells = [[Int32]](repeating: [], count: nx * ny)
        xs = []; ys = []
        xs.reserveCapacity(points.count); ys.reserveCapacity(points.count)
        for p in points { append(p) }
    }

    /// A cell that holds about one point, which is the size that balances the
    /// walk (fewer points to reject) against the cell count (fewer cells to
    /// visit). A set that lies along a line has no area to divide, so it is
    /// spaced along its one live axis instead.
    private static func automaticCellSize(_ width: Double, _ height: Double,
                                          _ count: Int) -> Double {
        let span = Swift.max(width, height)
        guard count > 1, span > 0, span.isFinite else { return 1 }
        if Swift.min(width, height) <= 0 { return span / Double(count) }
        return (width * height / Double(count)).squareRoot()
    }

    /// The cell size and cell counts to really use: the asked-for size, doubled
    /// until the grid fits inside a sane number of cells.
    ///
    /// Without this an awkward set takes an absurd amount of memory for cells
    /// that hold nothing. A thousand points along a line, sized by their spacing,
    /// would ask for a million cells across and one cell down.
    private static func fit(_ width: Double, _ height: Double,
                            _ size: Double, _ count: Int) -> (size: Double, nx: Int, ny: Int) {
        var size = Swift.max(size, 1e-9)
        let cap = Swift.max(1 << 20, 4 * count)
        // One more cell each way, because snapping the corner down onto the
        // lattice can push the far edge into the next cell.
        var nx = spanCells(width + size, size), ny = spanCells(height + size, size)
        while nx > cap / Swift.max(ny, 1) {
            size *= 2
            nx = spanCells(width + size, size); ny = spanCells(height + size, size)
            if nx == 1 && ny == 1 { break }
        }
        return (size, nx, ny)
    }

    init(bounds: Rectangle, cellSize size: Double) {
        let fitted = CellGrid.fit(bounds.width, bounds.height, size, 0)
        cellSize = fitted.size; nx = fitted.nx; ny = fitted.ny
        minX = CellGrid.snapped(bounds.x, cellSize)
        minY = CellGrid.snapped(bounds.y, cellSize)
        cells = [[Int32]](repeating: [], count: nx * ny)
        xs = []; ys = []
    }

    /// The lower corner moved down onto the lattice of cells that runs through
    /// the origin.
    ///
    /// This is what makes a cell size cut the plane the same way every time.
    /// Anchored to the point set instead, a grid rebuilt after the points moved
    /// would sort them into differently placed cells, and a walk over them would
    /// report the same neighbors in a different order, which is enough to move
    /// the last digits of a sum and, over enough steps, the picture.
    private static func snapped(_ value: Double, _ size: Double) -> Double {
        guard value.isFinite, (value / size).isFinite else { return value }
        return (value / size).rounded(.down) * size
    }

    /// The cell count that covers `extent`, at least one and bounded so that a
    /// stray coordinate cannot ask for an unreasonable allocation. The bound is
    /// applied before the conversion to `Int`, which traps on a value a `Double`
    /// can hold and an `Int` cannot.
    private static func spanCells(_ extent: Double, _ size: Double) -> Int {
        guard extent.isFinite, extent > 0 else { return 1 }
        let span = (extent / size).rounded(.down) + 1
        return Swift.max(1, Int(Swift.min(span, Double(1 << 22))))
    }

    /// Add a point, growing the box when it lands outside.
    ///
    /// The growth is geometric (a quarter of the current span past the point that
    /// caused it), so a set that spreads outward as it grows, which is what
    /// aggregation does, pays for the rebuild a shrinking share of the time.
    mutating func insert(_ p: Vector2) {
        let fi = (p.x - minX) / cellSize, fj = (p.y - minY) / cellSize
        if fi >= 0, fj >= 0, fi < Double(nx), fj < Double(ny) {
            append(p)
        } else {
            rebuild(including: p)
        }
    }

    /// Place a point known to be inside the box.
    private mutating func append(_ p: Vector2) {
        let index = Int32(xs.count)
        xs.append(p.x); ys.append(p.y)
        let i = CellGrid.clamped((p.x - minX) / cellSize, nx)
        let j = CellGrid.clamped((p.y - minY) / cellSize, ny)
        cells[i * ny + j].append(index)
    }

    private mutating func rebuild(including p: Vector2) {
        var loX = Swift.min(minX, p.x), loY = Swift.min(minY, p.y)
        var hiX = Swift.max(minX + Double(nx) * cellSize, p.x)
        var hiY = Swift.max(minY + Double(ny) * cellSize, p.y)
        let padX = Swift.max((hiX - loX) * 0.25, cellSize)
        let padY = Swift.max((hiY - loY) * 0.25, cellSize)
        loX -= padX; loY -= padY; hiX += padX; hiY += padY

        let oldXs = xs, oldYs = ys
        let fitted = CellGrid.fit(hiX - loX, hiY - loY, cellSize, oldXs.count + 1)
        cellSize = fitted.size; nx = fitted.nx; ny = fitted.ny
        minX = CellGrid.snapped(loX, cellSize); minY = CellGrid.snapped(loY, cellSize)
        cells = [[Int32]](repeating: [], count: nx * ny)
        xs = []; ys = []
        xs.reserveCapacity(oldXs.count + 1); ys.reserveCapacity(oldYs.count + 1)
        for k in oldXs.indices { append(Vector2(oldXs[k], oldYs[k])) }
        append(p)
    }

    // MARK: Queries

    /// The query point's cell (clamped into the grid) and whether it really lies
    /// inside the box. Inside, the ring bound is one cell tighter: after ring `r`
    /// nothing unvisited can be nearer than `r * cellSize`, while a clamped
    /// outside point only guarantees `(r - 1) * cellSize`.
    private func home(_ px: Double, _ py: Double) -> (i: Int, j: Int, inBox: Bool) {
        let fi = (px - minX) / cellSize, fj = (py - minY) / cellSize
        let i = CellGrid.clamped(fi, nx), j = CellGrid.clamped(fj, ny)
        let inBox = fi >= 0 && fi < Double(nx) && fj >= 0 && fj < Double(ny)
        return (i, j, inBox)
    }

    /// A cell coordinate cut to `0 ..< n`, with the cut made in floating point
    /// because converting a far-out coordinate to `Int` first would trap.
    private static func clamped(_ f: Double, _ n: Int) -> Int {
        guard f.isFinite else { return 0 }
        return Int(Swift.min(Swift.max(f.rounded(.down), 0), Double(n - 1)))
    }

    /// The block of cells a radius query around `p` can reach, already cut to the
    /// grid. The block is measured from the point's **true** cell rather than a
    /// clamped one, so a query outside the box reads the cells that are really
    /// within reach and no others.
    private func block(_ px: Double, _ py: Double, _ radius: Double)
        -> (iLo: Int, iHi: Int, jLo: Int, jHi: Int)? {
        let fi = (px - minX) / cellSize, fj = (py - minY) / cellSize
        guard fi.isFinite, fj.isFinite else { return nil }
        let reach = (radius / cellSize).rounded(.up)
        guard reach.isFinite else { return (0, nx - 1, 0, ny - 1) }
        let loI = fi.rounded(.down) - reach, hiI = fi.rounded(.down) + reach
        let loJ = fj.rounded(.down) - reach, hiJ = fj.rounded(.down) + reach
        guard hiI >= 0, hiJ >= 0, loI < Double(nx), loJ < Double(ny) else { return nil }
        return (CellGrid.clamped(loI, nx), CellGrid.clamped(hiI, nx),
                CellGrid.clamped(loJ, ny), CellGrid.clamped(hiJ, ny))
    }

    func forEachNeighbor(of p: Vector2, within radius: Double, skipping: Int,
                      _ body: (Int, Double) -> Void) {
        guard let b = block(p.x, p.y, radius) else { return }
        let px = p.x, py = p.y, r2 = radius * radius
        var i = b.iLo
        while i <= b.iHi {
            var j = b.jLo
            while j <= b.jHi {
                for entry in cells[i * ny + j] {
                    let index = Int(entry)
                    if index == skipping { continue }
                    let dx = xs[index] - px, dy = ys[index] - py
                    let d2 = dx * dx + dy * dy
                    if d2 <= r2 { body(index, d2) }
                }
                j += 1
            }
            i += 1
        }
    }

    func anyNeighbor(of p: Vector2, within radius: Double, skipping: Int) -> Int? {
        guard let b = block(p.x, p.y, radius) else { return nil }
        let px = p.x, py = p.y, r2 = radius * radius
        var i = b.iLo
        while i <= b.iHi {
            var j = b.jLo
            while j <= b.jHi {
                for entry in cells[i * ny + j] {
                    let index = Int(entry)
                    if index == skipping { continue }
                    let dx = xs[index] - px, dy = ys[index] - py
                    if dx * dx + dy * dy <= r2 { return index }
                }
                j += 1
            }
            i += 1
        }
        return nil
    }

    private var maxRing: Int { Swift.max(nx, ny) }

    /// Walk the cells of ring `r` around `(ci, cj)` in a fixed order.
    private func forRing(_ r: Int, _ ci: Int, _ cj: Int, _ visit: (Int) -> Void) {
        let iLo = Swift.max(ci - r, 0), iHi = Swift.min(ci + r, nx - 1)
        let jLo = Swift.max(cj - r, 0), jHi = Swift.min(cj + r, ny - 1)
        var i = iLo
        while i <= iHi {
            let onI = abs(i - ci) == r
            var j = jLo
            while j <= jHi {
                if r == 0 || onI || abs(j - cj) == r { visit(i * ny + j) }
                j += 1
            }
            i += 1
        }
    }

    /// The nearest point, found by growing rings of cells outward.
    ///
    /// The search may stop only once the best find is inside the ring bound.
    /// Stopping at the first find instead locks the answer to the cell lattice,
    /// because a point in the next ring can still be nearer than one in a corner
    /// of this one.
    func nearest(to p: Vector2) -> Int? {
        let px = p.x, py = p.y
        let c = home(px, py)
        var best = -1, bestD2 = Double.infinity
        var ring = 0
        while ring <= maxRing {
            forRing(ring, c.i, c.j) { cell in
                for entry in cells[cell] {
                    let index = Int(entry)
                    let dx = xs[index] - px, dy = ys[index] - py
                    let d2 = dx * dx + dy * dy
                    // The first candidate always wins. Testing the distance
                    // alone would answer "nothing" for a set that is really
                    // there, because a coordinate large enough to square into
                    // infinity is not less than the infinity we start from.
                    if best < 0 || d2 < bestD2 || (d2 == bestD2 && index < best) {
                        bestD2 = d2; best = index
                    }
                }
            }
            if best >= 0 {
                // Strictly inside the bound, never equal to it: a point exactly
                // at the bound could still be tied with the best find, and a tie
                // has to answer with the lower index.
                let safe = Double(c.inBox ? ring : ring - 1) * cellSize
                if safe >= 0, bestD2 < safe * safe { break }
            }
            ring += 1
        }
        return best >= 0 ? best : nil
    }

    func kNearest(_ want: Int, to p: Vector2) -> [Int] {
        let px = p.x, py = p.y
        let c = home(px, py)
        var found: [(d2: Double, i: Int)] = []
        found.reserveCapacity(want + 32)
        var ring = 0
        while ring <= maxRing {
            forRing(ring, c.i, c.j) { cell in
                for entry in cells[cell] {
                    let index = Int(entry)
                    let dx = xs[index] - px, dy = ys[index] - py
                    found.append((dx * dx + dy * dy, index))
                }
            }
            if found.count >= want {
                found.sort { $0.d2 != $1.d2 ? $0.d2 < $1.d2 : $0.i < $1.i }
                if found.count > want + 32 { found.removeLast(found.count - want - 32) }
                let safe = Double(c.inBox ? ring : ring - 1) * cellSize
                if safe >= 0, found[want - 1].d2 < safe * safe { break }
            }
            ring += 1
        }
        found.sort { $0.d2 != $1.d2 ? $0.d2 < $1.d2 : $0.i < $1.i }
        return found.prefix(want).map(\.i)
    }

    func forPoints(in region: Rectangle, _ body: (Int) -> Void) {
        let loX = region.x, loY = region.y
        let hiX = region.x + region.width, hiY = region.y + region.height
        let fiLo = (loX - minX) / cellSize, fjLo = (loY - minY) / cellSize
        let fiHi = (hiX - minX) / cellSize, fjHi = (hiY - minY) / cellSize
        guard fiLo.isFinite, fjLo.isFinite, fiHi.isFinite, fjHi.isFinite else { return }
        guard fiHi >= 0, fjHi >= 0, fiLo < Double(nx), fjLo < Double(ny) else { return }
        let iLo = CellGrid.clamped(fiLo, nx), iHi = CellGrid.clamped(fiHi, nx)
        let jLo = CellGrid.clamped(fjLo, ny), jHi = CellGrid.clamped(fjHi, ny)
        var i = iLo
        while i <= iHi {
            var j = jLo
            while j <= jHi {
                for entry in cells[i * ny + j] {
                    let index = Int(entry)
                    let x = xs[index], y = ys[index]
                    if x >= loX, x <= hiX, y >= loY, y <= hiY { body(index) }
                }
                j += 1
            }
            i += 1
        }
    }
}
