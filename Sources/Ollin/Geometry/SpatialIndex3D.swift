import Foundation

/// A spatial index over a set of points in space: ``SpatialIndex`` for
/// `Vector3`, answering "what is near here" without comparing against every
/// point.
///
/// A point cloud, a swarm in space, a scatter over a surface: whenever a loop
/// over points in space hides a second loop over the same points, this is the
/// structure that takes the second loop out.
///
/// ```swift
/// let index = SpatialIndex3D(positions)
/// if let i = index.nearest(to: probe) { drawSphere(at: positions[i], radius: 0.1) }
/// for j in index.neighbors(of: probe, within: 0.5) { drawLine3D(probe, positions[j]) }
/// ```
///
/// Every query answers with **indices into `points`**, so a sketch keeps its own
/// payload beside the positions and reads it back with the same index.
///
/// ## The two kinds
///
/// - ``Kind/grid`` (the default) sorts the points into cubic cells and reads the
///   block of cells a query reaches. It is the right choice when the points are
///   spread through the volume at a similar density, and it is the only kind that
///   takes new points cheaply after it is built.
/// - ``Kind/tree`` splits the set in half, then each half in half again, along
///   whichever axis is widest. It stays fast when the points are gathered into
///   tight clumps with wide empty space between them, or lie on a surface,
///   where a grid has to walk many empty cells to reach them.
///
/// The kind is a speed choice and never a correctness one: every query that
/// answers with an array answers identically, down to the order, and the two
/// forms that hand back one point at a time walk in their own kind's fixed
/// order.
///
/// ## Reproducibility
///
/// The rules of the flat index hold here: a query returns its indices in a fixed
/// order (ascending distance and then ascending index, or ascending index for
/// the region and neighbor lists), ties break toward the lower index, and the
/// cells are cut on the lattice through the origin, so a rebuilt index sorts
/// moved points into the same cells and a walk over them keeps its order.
public struct SpatialIndex3D: Sendable {

    /// How an index arranges its points. Both kinds answer the same queries
    /// with the same results; they differ in what they are fast at.
    public enum Kind: Sendable, Hashable {
        /// Cubic cells of a fixed size. Fast for evenly spread points, and the
        /// kind that accepts new points after the build.
        case grid
        /// A k-d tree: repeated halving along the widest axis. Fast for
        /// clumped points and points on a surface, and rebuilt when new
        /// points arrive.
        case tree
    }

    /// The points the index was built over, in the order they were given.
    /// A point added later sits at the end, at the index ``insert(_:)`` returned.
    public private(set) var points: [Vector3]

    /// Which arrangement this index uses.
    public let kind: Kind

    private var grid: CellGrid3
    private var tree: KDTree3?

    // MARK: - Building

    /// An index over `points`.
    ///
    /// With no `cellSize`, a grid sizes its cells so that a cell holds about one
    /// point. Pass the radius you plan to query with when you know it: a cell
    /// equal to that radius reads a 3 by 3 by 3 block and nothing more.
    public init(_ points: [Vector3], kind: Kind = .grid, cellSize: Double? = nil) {
        self.points = points
        self.kind = kind
        self.grid = CellGrid3(points: points, cellSize: cellSize)
        self.tree = kind == .tree ? KDTree3(points: points) : nil
    }

    /// An empty index ready to take points inside `bounds`, for the sketches
    /// that grow a set rather than start with one. A point that lands outside
    /// `bounds` is still indexed correctly; the box simply grows to take it.
    public init(bounds: Box3, cellSize: Double, kind: Kind = .grid) {
        self.points = []
        self.kind = kind
        self.grid = CellGrid3(bounds: bounds, cellSize: cellSize)
        self.tree = kind == .tree ? KDTree3(points: []) : nil
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
    public mutating func insert(_ point: Vector3) -> Int {
        let index = points.count
        points.append(point)
        grid.insert(point)
        if kind == .tree { tree = KDTree3(points: points) }
        return index
    }

    // MARK: - Queries

    /// The index of the point nearest to `p`, or nil when the index is empty.
    /// Equal distances answer with the lower index.
    public func nearest(to p: Vector3) -> Int? {
        guard !points.isEmpty else { return nil }
        if let tree { return tree.nearest(to: p) }
        return grid.nearest(to: p)
    }

    /// The indices of the `k` points nearest to `p`, ascending by distance and
    /// then by index. Fewer come back only when the set is smaller than `k`.
    public func kNearest(_ k: Int, to p: Vector3) -> [Int] {
        guard k > 0, !points.isEmpty else { return [] }
        let want = Swift.min(k, points.count)
        if let tree { return tree.kNearest(want, to: p) }
        return grid.kNearest(want, to: p)
    }

    /// The indices of every point within `radius` of `p`, ascending by index.
    /// The boundary counts as inside.
    public func neighbors(of p: Vector3, within radius: Double) -> [Int] {
        var found: [Int] = []
        forEachNeighbor(of: p, within: radius) { index, _ in found.append(index) }
        found.sort()
        return found
    }

    /// The indices of every point within `radius` of the point at `index`,
    /// ascending by index, leaving out that point itself.
    public func neighbors(of index: Int, within radius: Double) -> [Int] {
        var found: [Int] = []
        forEachNeighbor(of: index, within: radius) { other, _ in found.append(other) }
        found.sort()
        return found
    }

    /// Visit every point within `radius` of `p` without building an array.
    /// `body` receives the point's index and its **squared** distance to `p`.
    public func forEachNeighbor(of p: Vector3, within radius: Double,
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

    /// The first point found within `radius` of `p`, or nil when there is none,
    /// picked in the index's own fixed walk order.
    public func anyNeighbor(of p: Vector3, within radius: Double) -> Int? {
        guard !points.isEmpty, radius > 0 else { return nil }
        if let tree { return tree.anyNeighbor(of: p, within: radius, skipping: -1) }
        return grid.anyNeighbor(of: p, within: radius, skipping: -1)
    }

    /// Whether any point lies within `radius` of `p`.
    public func hasNeighbor(of p: Vector3, within radius: Double) -> Bool {
        anyNeighbor(of: p, within: radius) != nil
    }

    /// The indices of every point inside `region`, ascending by index. The
    /// faces count as inside, matching `Box3.contains(_:)`.
    public func indices(in region: Box3) -> [Int] {
        guard !points.isEmpty else { return [] }
        var found: [Int] = []
        if let tree { tree.forPoints(in: region) { found.append($0) } }
        else { grid.forPoints(in: region) { found.append($0) } }
        found.sort()
        return found
    }
}

// MARK: - The grid backing

/// A uniform grid of cubic cells over a growing set of points in space, the
/// twin of the flat index's `CellGrid`: flat coordinate arrays plus one list
/// of point indices per cell, so that a point can be added in place and the
/// inner loop stays plain arithmetic.
struct CellGrid3 {

    private(set) var cellSize: Double
    private var minX: Double, minY: Double, minZ: Double
    private var nx: Int, ny: Int, nz: Int
    /// Point indices per cell, `(i * ny + j) * nz + k`, each cell ascending by
    /// index because points arrive in index order.
    private var cells: [[Int32]]
    private var xs: [Double], ys: [Double], zs: [Double]

    // MARK: Building

    init(points: [Vector3], cellSize explicit: Double?) {
        var loX = Double.infinity, loY = Double.infinity, loZ = Double.infinity
        var hiX = -Double.infinity, hiY = -Double.infinity, hiZ = -Double.infinity
        for p in points {
            if p.x < loX { loX = p.x }; if p.x > hiX { hiX = p.x }
            if p.y < loY { loY = p.y }; if p.y > hiY { hiY = p.y }
            if p.z < loZ { loZ = p.z }; if p.z > hiZ { hiZ = p.z }
        }
        if points.isEmpty { loX = 0; loY = 0; loZ = 0; hiX = 0; hiY = 0; hiZ = 0 }

        let width = hiX - loX, height = hiY - loY, depth = hiZ - loZ
        let size = explicit ?? CellGrid3.automaticCellSize(width, height, depth, points.count)
        let fitted = CellGrid3.fit(width, height, depth, size, points.count)
        cellSize = fitted.size; nx = fitted.nx; ny = fitted.ny; nz = fitted.nz
        minX = CellGrid3.snapped(loX, cellSize)
        minY = CellGrid3.snapped(loY, cellSize)
        minZ = CellGrid3.snapped(loZ, cellSize)
        cells = [[Int32]](repeating: [], count: nx * ny * nz)
        xs = []; ys = []; zs = []
        xs.reserveCapacity(points.count); ys.reserveCapacity(points.count)
        zs.reserveCapacity(points.count)
        for p in points { append(p) }
    }

    /// A cell that holds about one point. A set that lies on a plane or along
    /// a line has no volume to divide, so it is spaced over the axes it does
    /// have extent on.
    private static func automaticCellSize(_ width: Double, _ height: Double,
                                          _ depth: Double, _ count: Int) -> Double {
        let span = Swift.max(width, Swift.max(height, depth))
        guard count > 1, span > 0, span.isFinite else { return 1 }
        var measure = 1.0, live = 0
        for extent in [width, height, depth] where extent > 0 { measure *= extent; live += 1 }
        return pow(measure / Double(count), 1 / Double(live))
    }

    /// The cell size and counts to really use: the asked-for size, doubled
    /// until the grid fits inside a sane number of cells.
    private static func fit(_ width: Double, _ height: Double, _ depth: Double,
                            _ size: Double, _ count: Int)
        -> (size: Double, nx: Int, ny: Int, nz: Int) {
        var size = Swift.max(size, 1e-9)
        let cap = Swift.max(1 << 20, 4 * count)
        var nx = spanCells(width + size, size)
        var ny = spanCells(height + size, size)
        var nz = spanCells(depth + size, size)
        while nx > cap / Swift.max(ny * nz, 1) {
            size *= 2
            nx = spanCells(width + size, size)
            ny = spanCells(height + size, size)
            nz = spanCells(depth + size, size)
            if nx == 1 && ny == 1 && nz == 1 { break }
        }
        return (size, nx, ny, nz)
    }

    init(bounds: Box3, cellSize size: Double) {
        let extent = bounds.size
        let fitted = CellGrid3.fit(extent.x, extent.y, extent.z, size, 0)
        cellSize = fitted.size; nx = fitted.nx; ny = fitted.ny; nz = fitted.nz
        minX = CellGrid3.snapped(bounds.min.x, cellSize)
        minY = CellGrid3.snapped(bounds.min.y, cellSize)
        minZ = CellGrid3.snapped(bounds.min.z, cellSize)
        cells = [[Int32]](repeating: [], count: nx * ny * nz)
        xs = []; ys = []; zs = []
    }

    /// The lower corner moved down onto the lattice of cells that runs through
    /// the origin, so a cell size cuts space the same way every time.
    private static func snapped(_ value: Double, _ size: Double) -> Double {
        guard value.isFinite, (value / size).isFinite else { return value }
        return (value / size).rounded(.down) * size
    }

    /// The cell count that covers `extent`, at least one and bounded before the
    /// conversion to `Int`, which traps on a value a `Double` can hold.
    private static func spanCells(_ extent: Double, _ size: Double) -> Int {
        guard extent.isFinite, extent > 0 else { return 1 }
        let span = (extent / size).rounded(.down) + 1
        return Swift.max(1, Int(Swift.min(span, Double(1 << 22))))
    }

    /// Add a point, growing the box when it lands outside.
    mutating func insert(_ p: Vector3) {
        let fi = (p.x - minX) / cellSize, fj = (p.y - minY) / cellSize, fk = (p.z - minZ) / cellSize
        if fi >= 0, fj >= 0, fk >= 0, fi < Double(nx), fj < Double(ny), fk < Double(nz) {
            append(p)
        } else {
            rebuild(including: p)
        }
    }

    private mutating func append(_ p: Vector3) {
        let index = Int32(xs.count)
        xs.append(p.x); ys.append(p.y); zs.append(p.z)
        let i = CellGrid3.clamped((p.x - minX) / cellSize, nx)
        let j = CellGrid3.clamped((p.y - minY) / cellSize, ny)
        let k = CellGrid3.clamped((p.z - minZ) / cellSize, nz)
        cells[(i * ny + j) * nz + k].append(index)
    }

    /// Grow geometrically (a quarter of the span past the point that caused
    /// it), so a set that spreads outward pays for the rebuild a shrinking
    /// share of the time.
    private mutating func rebuild(including p: Vector3) {
        var loX = Swift.min(minX, p.x), loY = Swift.min(minY, p.y), loZ = Swift.min(minZ, p.z)
        var hiX = Swift.max(minX + Double(nx) * cellSize, p.x)
        var hiY = Swift.max(minY + Double(ny) * cellSize, p.y)
        var hiZ = Swift.max(minZ + Double(nz) * cellSize, p.z)
        let padX = Swift.max((hiX - loX) * 0.25, cellSize)
        let padY = Swift.max((hiY - loY) * 0.25, cellSize)
        let padZ = Swift.max((hiZ - loZ) * 0.25, cellSize)
        loX -= padX; loY -= padY; loZ -= padZ; hiX += padX; hiY += padY; hiZ += padZ

        let oldXs = xs, oldYs = ys, oldZs = zs
        let fitted = CellGrid3.fit(hiX - loX, hiY - loY, hiZ - loZ, cellSize, oldXs.count + 1)
        cellSize = fitted.size; nx = fitted.nx; ny = fitted.ny; nz = fitted.nz
        minX = CellGrid3.snapped(loX, cellSize)
        minY = CellGrid3.snapped(loY, cellSize)
        minZ = CellGrid3.snapped(loZ, cellSize)
        cells = [[Int32]](repeating: [], count: nx * ny * nz)
        xs = []; ys = []; zs = []
        xs.reserveCapacity(oldXs.count + 1); ys.reserveCapacity(oldYs.count + 1)
        zs.reserveCapacity(oldZs.count + 1)
        for k in oldXs.indices { append(Vector3(oldXs[k], oldYs[k], oldZs[k])) }
        append(p)
    }

    // MARK: Queries

    /// The query point's cell (clamped into the grid) and whether it really
    /// lies inside the box: inside, the ring bound is one cell tighter.
    private func home(_ px: Double, _ py: Double, _ pz: Double)
        -> (i: Int, j: Int, k: Int, inBox: Bool) {
        let fi = (px - minX) / cellSize, fj = (py - minY) / cellSize, fk = (pz - minZ) / cellSize
        let i = CellGrid3.clamped(fi, nx), j = CellGrid3.clamped(fj, ny), k = CellGrid3.clamped(fk, nz)
        let inBox = fi >= 0 && fi < Double(nx) && fj >= 0 && fj < Double(ny)
            && fk >= 0 && fk < Double(nz)
        return (i, j, k, inBox)
    }

    /// A cell coordinate cut to `0 ..< n`, cut in floating point first because
    /// converting a far-out coordinate to `Int` would trap.
    private static func clamped(_ f: Double, _ n: Int) -> Int {
        guard f.isFinite else { return 0 }
        return Int(Swift.min(Swift.max(f.rounded(.down), 0), Double(n - 1)))
    }

    /// The block of cells a radius query around `p` can reach, measured from
    /// the point's **true** cell rather than a clamped one.
    private func block(_ px: Double, _ py: Double, _ pz: Double, _ radius: Double)
        -> (iLo: Int, iHi: Int, jLo: Int, jHi: Int, kLo: Int, kHi: Int)? {
        let fi = (px - minX) / cellSize, fj = (py - minY) / cellSize, fk = (pz - minZ) / cellSize
        guard fi.isFinite, fj.isFinite, fk.isFinite else { return nil }
        let reach = (radius / cellSize).rounded(.up)
        guard reach.isFinite else { return (0, nx - 1, 0, ny - 1, 0, nz - 1) }
        let loI = fi.rounded(.down) - reach, hiI = fi.rounded(.down) + reach
        let loJ = fj.rounded(.down) - reach, hiJ = fj.rounded(.down) + reach
        let loK = fk.rounded(.down) - reach, hiK = fk.rounded(.down) + reach
        guard hiI >= 0, hiJ >= 0, hiK >= 0,
              loI < Double(nx), loJ < Double(ny), loK < Double(nz) else { return nil }
        return (CellGrid3.clamped(loI, nx), CellGrid3.clamped(hiI, nx),
                CellGrid3.clamped(loJ, ny), CellGrid3.clamped(hiJ, ny),
                CellGrid3.clamped(loK, nz), CellGrid3.clamped(hiK, nz))
    }

    func forEachNeighbor(of p: Vector3, within radius: Double, skipping: Int,
                         _ body: (Int, Double) -> Void) {
        guard let b = block(p.x, p.y, p.z, radius) else { return }
        let px = p.x, py = p.y, pz = p.z, r2 = radius * radius
        var i = b.iLo
        while i <= b.iHi {
            var j = b.jLo
            while j <= b.jHi {
                var k = b.kLo
                while k <= b.kHi {
                    for entry in cells[(i * ny + j) * nz + k] {
                        let index = Int(entry)
                        if index == skipping { continue }
                        let dx = xs[index] - px, dy = ys[index] - py, dz = zs[index] - pz
                        let d2 = dx * dx + dy * dy + dz * dz
                        if d2 <= r2 { body(index, d2) }
                    }
                    k += 1
                }
                j += 1
            }
            i += 1
        }
    }

    func anyNeighbor(of p: Vector3, within radius: Double, skipping: Int) -> Int? {
        guard let b = block(p.x, p.y, p.z, radius) else { return nil }
        let px = p.x, py = p.y, pz = p.z, r2 = radius * radius
        var i = b.iLo
        while i <= b.iHi {
            var j = b.jLo
            while j <= b.jHi {
                var k = b.kLo
                while k <= b.kHi {
                    for entry in cells[(i * ny + j) * nz + k] {
                        let index = Int(entry)
                        if index == skipping { continue }
                        let dx = xs[index] - px, dy = ys[index] - py, dz = zs[index] - pz
                        if dx * dx + dy * dy + dz * dz <= r2 { return index }
                    }
                    k += 1
                }
                j += 1
            }
            i += 1
        }
        return nil
    }

    private var maxRing: Int { Swift.max(nx, Swift.max(ny, nz)) }

    /// Walk the cells of shell `r` around `(ci, cj, ck)` in a fixed order: the
    /// cells whose largest coordinate offset is exactly `r`.
    private func forRing(_ r: Int, _ ci: Int, _ cj: Int, _ ck: Int, _ visit: (Int) -> Void) {
        let iLo = Swift.max(ci - r, 0), iHi = Swift.min(ci + r, nx - 1)
        let jLo = Swift.max(cj - r, 0), jHi = Swift.min(cj + r, ny - 1)
        let kLo = Swift.max(ck - r, 0), kHi = Swift.min(ck + r, nz - 1)
        var i = iLo
        while i <= iHi {
            let onI = abs(i - ci) == r
            var j = jLo
            while j <= jHi {
                let onFace = r == 0 || onI || abs(j - cj) == r
                if onFace {
                    var k = kLo
                    while k <= kHi { visit((i * ny + j) * nz + k); k += 1 }
                } else {
                    // Inside the shell on both other axes: only the two faces
                    // at the ends of this one belong to the ring.
                    if ck - r >= 0 { visit((i * ny + j) * nz + (ck - r)) }
                    if ck + r < nz { visit((i * ny + j) * nz + (ck + r)) }
                }
                j += 1
            }
            i += 1
        }
    }

    /// The nearest point, found by growing shells of cells outward, stopping
    /// only once the best find is strictly inside the shell bound.
    func nearest(to p: Vector3) -> Int? {
        let px = p.x, py = p.y, pz = p.z
        let c = home(px, py, pz)
        var best = -1, bestD2 = Double.infinity
        var ring = 0
        while ring <= maxRing {
            forRing(ring, c.i, c.j, c.k) { cell in
                for entry in cells[cell] {
                    let index = Int(entry)
                    let dx = xs[index] - px, dy = ys[index] - py, dz = zs[index] - pz
                    let d2 = dx * dx + dy * dy + dz * dz
                    // The first candidate always wins: a coordinate that squares
                    // into infinity is not less than the infinity we start from.
                    if best < 0 || d2 < bestD2 || (d2 == bestD2 && index < best) {
                        bestD2 = d2; best = index
                    }
                }
            }
            if best >= 0 {
                let safe = Double(c.inBox ? ring : ring - 1) * cellSize
                if safe >= 0, bestD2 < safe * safe { break }
            }
            ring += 1
        }
        return best >= 0 ? best : nil
    }

    func kNearest(_ want: Int, to p: Vector3) -> [Int] {
        let px = p.x, py = p.y, pz = p.z
        let c = home(px, py, pz)
        var found: [(d2: Double, i: Int)] = []
        found.reserveCapacity(want + 32)
        var ring = 0
        while ring <= maxRing {
            forRing(ring, c.i, c.j, c.k) { cell in
                for entry in cells[cell] {
                    let index = Int(entry)
                    let dx = xs[index] - px, dy = ys[index] - py, dz = zs[index] - pz
                    found.append((dx * dx + dy * dy + dz * dz, index))
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

    func forPoints(in region: Box3, _ body: (Int) -> Void) {
        let loX = region.min.x, loY = region.min.y, loZ = region.min.z
        let hiX = region.max.x, hiY = region.max.y, hiZ = region.max.z
        let fiLo = (loX - minX) / cellSize, fjLo = (loY - minY) / cellSize, fkLo = (loZ - minZ) / cellSize
        let fiHi = (hiX - minX) / cellSize, fjHi = (hiY - minY) / cellSize, fkHi = (hiZ - minZ) / cellSize
        guard fiLo.isFinite, fjLo.isFinite, fkLo.isFinite,
              fiHi.isFinite, fjHi.isFinite, fkHi.isFinite else { return }
        guard fiHi >= 0, fjHi >= 0, fkHi >= 0,
              fiLo < Double(nx), fjLo < Double(ny), fkLo < Double(nz) else { return }
        let iLo = CellGrid3.clamped(fiLo, nx), iHi = CellGrid3.clamped(fiHi, nx)
        let jLo = CellGrid3.clamped(fjLo, ny), jHi = CellGrid3.clamped(fjHi, ny)
        let kLo = CellGrid3.clamped(fkLo, nz), kHi = CellGrid3.clamped(fkHi, nz)
        var i = iLo
        while i <= iHi {
            var j = jLo
            while j <= jHi {
                var k = kLo
                while k <= kHi {
                    for entry in cells[(i * ny + j) * nz + k] {
                        let index = Int(entry)
                        let x = xs[index], y = ys[index], z = zs[index]
                        if x >= loX, x <= hiX, y >= loY, y <= hiY, z >= loZ, z <= hiZ { body(index) }
                    }
                    k += 1
                }
                j += 1
            }
            i += 1
        }
    }
}
