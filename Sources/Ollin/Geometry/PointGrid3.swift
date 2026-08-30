import Foundation

/// A uniform-grid spatial index over a fixed set of 3D points: the CPU
/// neighbor-search substrate the point-cloud surfacing paths query millions of
/// times. Built once with counting sort into flat arrays, so construction is
/// O(n), queries touch no dictionaries, and every walk runs in a fixed order
/// (bucket by bucket, ascending point index within a bucket), which is what
/// keeps everything downstream byte-reproducible.
///
/// The queries deliberately work on flat scalar coordinate arrays with inline
/// arithmetic rather than `Vector3` operators or per-point closures: this
/// index sits under millions of field samples, and unoptimized builds (where
/// examples run) pay a function call for every non-transparent operation in
/// the hot loop, an order-of-magnitude difference at this call count.
struct PointGrid3 {

    let points: [Vector3]
    let cellSize: Double

    private let xs: [Double], ys: [Double], zs: [Double]
    private let minX: Double, minY: Double, minZ: Double
    private let nx: Int, ny: Int, nz: Int
    /// Prefix offsets into `sorted`, one per cell plus a terminator.
    private let cellStart: [Int]
    /// Point indices grouped by cell, ascending within each cell.
    private let sorted: [Int32]

    init(points: [Vector3], cellSize: Double) {
        self.points = points
        let size = max(cellSize, 1e-12)
        self.cellSize = size

        var xs = [Double](repeating: 0, count: points.count)
        var ys = xs, zs = xs
        var loX = Double.infinity, loY = Double.infinity, loZ = Double.infinity
        var hiX = -Double.infinity, hiY = -Double.infinity, hiZ = -Double.infinity
        for i in points.indices {
            let p = points[i]
            xs[i] = p.x; ys[i] = p.y; zs[i] = p.z
            if p.x < loX { loX = p.x }; if p.x > hiX { hiX = p.x }
            if p.y < loY { loY = p.y }; if p.y > hiY { hiY = p.y }
            if p.z < loZ { loZ = p.z }; if p.z > hiZ { hiZ = p.z }
        }
        if points.isEmpty { loX = 0; loY = 0; loZ = 0; hiX = 0; hiY = 0; hiZ = 0 }
        self.xs = xs; self.ys = ys; self.zs = zs
        minX = loX; minY = loY; minZ = loZ
        nx = max(1, Int((hiX - loX) / size) + 1)
        ny = max(1, Int((hiY - loY) / size) + 1)
        nz = max(1, Int((hiZ - loZ) / size) + 1)

        let cellCount = nx * ny * nz
        var counts = [Int](repeating: 0, count: cellCount + 1)
        var cellOf = [Int32](repeating: 0, count: points.count)
        for i in points.indices {
            let ci = min(max(Int((xs[i] - loX) / size), 0), nx - 1)
            let cj = min(max(Int((ys[i] - loY) / size), 0), ny - 1)
            let ck = min(max(Int((zs[i] - loZ) / size), 0), nz - 1)
            let c = (ck * ny + cj) * nx + ci
            cellOf[i] = Int32(c)
            counts[c + 1] += 1
        }
        for c in 1 ... cellCount { counts[c] += counts[c - 1] }
        var cursor = Array(counts[0 ..< cellCount])
        var order = [Int32](repeating: 0, count: points.count)
        for i in points.indices {   // ascending i keeps each bucket sorted by index
            let c = Int(cellOf[i])
            order[cursor[c]] = Int32(i)
            cursor[c] += 1
        }
        cellStart = counts
        sorted = order
    }

    /// The query point's cell coordinates (clamped into the grid) and whether
    /// it actually lies inside the grid's box. Inside, the ring bound is one
    /// cell tighter: after visiting ring r nothing unvisited can be nearer
    /// than `r * cellSize`; a clamped outside point only guarantees
    /// `(r - 1) * cellSize`.
    private func home(_ px: Double, _ py: Double, _ pz: Double)
        -> (i: Int, j: Int, k: Int, inBox: Bool) {
        let fi = (px - minX) / cellSize
        let fj = (py - minY) / cellSize
        let fk = (pz - minZ) / cellSize
        let i = min(max(Int(fi), 0), nx - 1)
        let j = min(max(Int(fj), 0), ny - 1)
        let k = min(max(Int(fk), 0), nz - 1)
        let inBox = fi >= 0 && fi < Double(nx) && fj >= 0 && fj < Double(ny)
                 && fk >= 0 && fk < Double(nz)
        return (i, j, k, inBox)
    }

    private var maxRing: Int { max(nx, max(ny, nz)) }

    /// The index of the point nearest to `p`, or nil for an empty set. The
    /// ring search may stop expanding only once the best find is inside the
    /// ring bound; stopping at first-found locks results to the lattice.
    func nearest(to p: Vector3) -> Int? {
        guard !points.isEmpty else { return nil }
        let px = p.x, py = p.y, pz = p.z
        let c = home(px, py, pz)
        var best = -1
        var bestD2 = Double.infinity
        var ring = 0
        while ring <= maxRing {
            let iLo = max(c.i - ring, 0), iHi = min(c.i + ring, nx - 1)
            let jLo = max(c.j - ring, 0), jHi = min(c.j + ring, ny - 1)
            let kLo = max(c.k - ring, 0), kHi = min(c.k + ring, nz - 1)
            var k = kLo
            while k <= kHi {
                let onK = abs(k - c.k) == ring
                var j = jLo
                while j <= jHi {
                    let onJK = onK || abs(j - c.j) == ring
                    var i = iLo
                    while i <= iHi {
                        if ring == 0 || onJK || abs(i - c.i) == ring {
                            let cell = (k * ny + j) * nx + i
                            var s = cellStart[cell]
                            let e = cellStart[cell + 1]
                            while s < e {
                                let index = Int(sorted[s])
                                let dx = xs[index] - px
                                let dy = ys[index] - py
                                let dz = zs[index] - pz
                                let d2 = dx * dx + dy * dy + dz * dz
                                if d2 < bestD2 { bestD2 = d2; best = index }
                                s += 1
                            }
                        }
                        i += 1
                    }
                    j += 1
                }
                k += 1
            }
            if best >= 0 {
                let safe = Double(c.inBox ? ring : ring - 1) * cellSize
                if safe >= 0, bestD2 < safe * safe { break }
            }
            ring += 1
        }
        return best >= 0 ? best : nil
    }

    /// The indices of the `k` points nearest to `p`, ascending by (distance,
    /// index). Fewer come back only when the set itself is smaller than `k`.
    func kNearest(_ k: Int, to p: Vector3) -> [Int] {
        guard k > 0, !points.isEmpty else { return [] }
        let want = min(k, points.count)
        let px = p.x, py = p.y, pz = p.z
        let c = home(px, py, pz)
        var found: [(d2: Double, i: Int)] = []
        found.reserveCapacity(want + 32)
        var ring = 0
        while ring <= maxRing {
            let iLo = max(c.i - ring, 0), iHi = min(c.i + ring, nx - 1)
            let jLo = max(c.j - ring, 0), jHi = min(c.j + ring, ny - 1)
            let kLo = max(c.k - ring, 0), kHi = min(c.k + ring, nz - 1)
            var ck = kLo
            while ck <= kHi {
                let onK = abs(ck - c.k) == ring
                var cj = jLo
                while cj <= jHi {
                    let onJK = onK || abs(cj - c.j) == ring
                    var ci = iLo
                    while ci <= iHi {
                        if ring == 0 || onJK || abs(ci - c.i) == ring {
                            let cell = (ck * ny + cj) * nx + ci
                            var s = cellStart[cell]
                            let e = cellStart[cell + 1]
                            while s < e {
                                let index = Int(sorted[s])
                                let dx = xs[index] - px
                                let dy = ys[index] - py
                                let dz = zs[index] - pz
                                found.append((dx * dx + dy * dy + dz * dz, index))
                                s += 1
                            }
                        }
                        ci += 1
                    }
                    cj += 1
                }
                ck += 1
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

    /// Visit every point within `radius` of `p`, in fixed (cell, index) order.
    /// The callback runs once per point actually inside the radius; the
    /// candidate rejection happens on the flat coordinates first.
    func forEachNeighbor(of p: Vector3, within radius: Double, _ body: (Int, Double) -> Void) {
        guard !points.isEmpty, radius > 0 else { return }
        let px = p.x, py = p.y, pz = p.z
        let c = home(px, py, pz)
        let reach = min(Int((radius / cellSize).rounded(.up)), maxRing)
        let r2 = radius * radius
        let iLo = max(c.i - reach, 0), iHi = min(c.i + reach, nx - 1)
        let jLo = max(c.j - reach, 0), jHi = min(c.j + reach, ny - 1)
        let kLo = max(c.k - reach, 0), kHi = min(c.k + reach, nz - 1)
        var k = kLo
        while k <= kHi {
            var j = jLo
            while j <= jHi {
                var i = iLo
                while i <= iHi {
                    let cell = (k * ny + j) * nx + i
                    var s = cellStart[cell]
                    let e = cellStart[cell + 1]
                    while s < e {
                        let index = Int(sorted[s])
                        let dx = xs[index] - px
                        let dy = ys[index] - py
                        let dz = zs[index] - pz
                        let d2 = dx * dx + dy * dy + dz * dz
                        if d2 <= r2 { body(index, d2) }
                        s += 1
                    }
                    i += 1
                }
                j += 1
            }
            k += 1
        }
    }
}
