import Foundation

// MARK: - Thinning to even spacing

/// The indices of the `count` points that thinning to even spacing keeps,
/// ascending. The most crowded point is dropped over and over: each carries the
/// weight of how closely its neighbors press on it, the heaviest goes, and the
/// ones around it grow lighter for its absence.
///
/// The wanted spacing is never stated. It falls out of the count and the area,
/// which is what lets this work on a surface, where a radius has no obvious
/// value, as readily as it works on a flat rectangle.
func blueNoiseSurvivors(of positions: [Vector3], count: Int, area: Double) -> [Int] {
    let m = positions.count
    guard count < m, count > 0, area > 0 else { return Array(0 ..< Swift.min(Swift.max(count, 0), m)) }

    // The radius at which `count` disks would just cover the area in a
    // honeycomb, which is as tight as circles ever pack.
    let rMax = (area / (2 * 3.0.squareRoot() * Double(count))).squareRoot()
    let dMax = 2 * rMax
    guard dMax > 0, dMax.isFinite else { return Array(0 ..< count) }

    // Pairs closer than this all count as equally crowded. Without the floor, a
    // pair that landed almost on top of each other outweighs everything else and
    // the pass spends its whole budget separating them.
    let dMin = dMax * 0.65 * (1 - pow(Double(count) / Double(m), 1.5))
    let reach2 = dMax * dMax

    // Weight falls to nothing at `dMax` and rises steeply as a pair closes: the
    // eighth power is what makes the nearest neighbor, not the general crowd,
    // decide who goes.
    @inline(__always) func weight(_ d2: Double) -> Double {
        let d = Swift.min(Swift.max(d2.squareRoot(), dMin), dMax)
        let t = 1 - d / dMax
        let t2 = t * t, t4 = t2 * t2
        return t4 * t4
    }

    let cells = ThinningCells(positions, cellSize: dMax)
    // Weights are kept in cell order, like the points. A dropped point's weight
    // becomes `gone`, which is also how its neighbors know to pass it over.
    let gone = -Double.infinity
    var weights = [Double](repeating: 0, count: m)
    cells.points.withUnsafeBufferPointer { p in
        cells.cell.withUnsafeBufferPointer { cellOf in
            cells.runs.withUnsafeBufferPointer { runs in
                weights.withUnsafeMutableBufferPointer { w in
                    for s in 0 ..< m {
                        let px = p[s].x, py = p[s].y, pz = p[s].z
                        var sum = 0.0
                        var r = Int(cellOf[s]) * 18
                        let end = r + 18
                        while r < end {
                            var q = Int(runs[r])
                            let stop = Int(runs[r + 1])
                            while q < stop {
                                let dx = p[q].x - px, dy = p[q].y - py, dz = p[q].z - pz
                                let d2 = dx * dx + dy * dy + dz * dz
                                if d2 <= reach2, q != s { sum += weight(d2) }
                                q += 1
                            }
                            r += 2
                        }
                        w[s] = sum
                    }

                    var queue = ThinningQueue(weights: w, original: cells.original)
                    var left = m
                    while left > count {
                        let top = queue.top
                        let s = Int(top.sample)
                        // The entry was made before the point's neighbors left. Its
                        // weight now is lower, so it goes back in at that weight.
                        if top.weight != w[s] { queue.lowerTop(to: w[s]); continue }
                        queue.removeTop()
                        w[s] = gone
                        left -= 1
                        let px = p[s].x, py = p[s].y, pz = p[s].z
                        var r = Int(cellOf[s]) * 18
                        let end = r + 18
                        while r < end {
                            var q = Int(runs[r])
                            let stop = Int(runs[r + 1])
                            while q < stop {
                                let dx = p[q].x - px, dy = p[q].y - py, dz = p[q].z - pz
                                let d2 = dx * dx + dy * dy + dz * dz
                                if d2 <= reach2, w[q] != gone { w[q] -= weight(d2) }
                                q += 1
                            }
                            r += 2
                        }
                    }
                }
            }
        }
    }

    var kept = [Bool](repeating: false, count: m)
    for s in 0 ..< m where weights[s] != gone { kept[Int(cells.original[s])] = true }
    var out: [Int] = []
    out.reserveCapacity(count)
    for i in 0 ..< m where kept[i] { out.append(i) }
    return out
}

/// The points renumbered cell by cell, with each occupied cell's neighbors
/// found once.
///
/// Space is cut into cubes the size of the thinning's reach, and the points
/// sorted by cube: cubes in (z, y, x) order, and within one cube by their
/// place in the input. A point's neighbors all sit in the 27 cubes around its
/// own, and those fall into nine runs (one per row of three along x), each
/// unbroken in the sorted order. The runs are looked up once per occupied cube
/// and kept, so a neighbor walk is nine ranges of the sorted points and
/// nothing else, in the same order a walk over a dense grid takes. That order
/// matters: it fixes how each weight's sum rounds.
///
/// Only occupied cubes cost anything. Points on a surface fill a thin shell of
/// a box whose cubes number in the tens of millions, which a dense grid would
/// have to hold and walk through.
private struct ThinningCells {

    /// The points, in cell order.
    let points: [Vector3]
    /// Where each point in cell order sat in the input.
    let original: [Int32]
    /// The occupied cube each point in cell order lies in.
    let cell: [Int32]
    /// Eighteen per occupied cube: the start and end, in cell order, of each of
    /// the nine runs around it, rows in (z, y) order. A row with nothing in it
    /// is an empty range.
    let runs: [Int32]

    init(_ positions: [Vector3], cellSize: Double) {
        let m = positions.count
        let size = Swift.max(cellSize, 1e-12)
        var loX = Double.infinity, loY = Double.infinity, loZ = Double.infinity
        var hiX = -Double.infinity, hiY = -Double.infinity, hiZ = -Double.infinity
        for p in positions {
            if p.x < loX { loX = p.x }; if p.x > hiX { hiX = p.x }
            if p.y < loY { loY = p.y }; if p.y > hiY { hiY = p.y }
            if p.z < loZ { loZ = p.z }; if p.z > hiZ { hiZ = p.z }
        }
        if positions.isEmpty { loX = 0; loY = 0; loZ = 0; hiX = 0; hiY = 0; hiZ = 0 }
        let nx = Swift.max(1, Int((hiX - loX) / size) + 1)
        let ny = Swift.max(1, Int((hiY - loY) / size) + 1)
        let nz = Swift.max(1, Int((hiZ - loZ) / size) + 1)

        var ci = [Int](repeating: 0, count: m), cj = ci, ck = ci
        for i in 0 ..< m {
            let p = positions[i]
            ci[i] = Swift.min(Swift.max(Int((p.x - loX) / size), 0), nx - 1)
            cj[i] = Swift.min(Swift.max(Int((p.y - loY) / size), 0), ny - 1)
            ck[i] = Swift.min(Swift.max(Int((p.z - loZ) / size), 0), nz - 1)
        }
        // Stable sorts by x, then y, then z leave the points in (z, y, x) order,
        // and in input order within a cube.
        var order = [Int32](0 ..< Int32(m))
        sortStably(&order, by: ci, below: nx)
        sortStably(&order, by: cj, below: ny)
        sortStably(&order, by: ck, below: nz)

        var points = [Vector3](repeating: .zero, count: m)
        var cell = [Int32](repeating: 0, count: m)
        var starts: [Int32] = []
        var cubeI: [Int] = [], cubeJ: [Int] = [], cubeK: [Int] = []
        for s in 0 ..< m {
            let i = Int(order[s])
            points[s] = positions[i]
            if s == 0 || ci[i] != cubeI[cubeI.count - 1] || cj[i] != cubeJ[cubeJ.count - 1]
                || ck[i] != cubeK[cubeK.count - 1] {
                starts.append(Int32(s))
                cubeI.append(ci[i]); cubeJ.append(cj[i]); cubeK.append(ck[i])
            }
            cell[s] = Int32(starts.count - 1)
        }
        let cubes = starts.count
        starts.append(Int32(m))

        // An open-addressed table from a cube's coordinates to its number, used
        // only here, while the runs are found.
        var capacity = 16
        while capacity < cubes * 2 { capacity <<= 1 }
        let mask = capacity - 1
        var slots = [Int32](repeating: -1, count: capacity)
        @inline(__always) func slot(_ i: Int, _ j: Int, _ k: Int) -> Int {
            var h = UInt64(truncatingIfNeeded: i) &* 0x9E37_79B9_7F4A_7C15
            h ^= UInt64(truncatingIfNeeded: j) &* 0xC2B2_AE3D_27D4_EB4F
            h ^= UInt64(truncatingIfNeeded: k) &* 0x1656_67B1_9E37_79F9
            h ^= h >> 29
            return Int(truncatingIfNeeded: h) & mask
        }
        for c in 0 ..< cubes {
            var h = slot(cubeI[c], cubeJ[c], cubeK[c])
            while slots[h] >= 0 { h = (h + 1) & mask }
            slots[h] = Int32(c)
        }
        @inline(__always) func cube(_ i: Int, _ j: Int, _ k: Int) -> Int {
            var h = slot(i, j, k)
            while true {
                let c = Int(slots[h])
                if c < 0 || (cubeI[c] == i && cubeJ[c] == j && cubeK[c] == k) { return c }
                h = (h + 1) & mask
            }
        }

        var runs = [Int32](repeating: 0, count: cubes * 18)
        for c in 0 ..< cubes {
            let i0 = cubeI[c], j0 = cubeJ[c], k0 = cubeK[c]
            var r = c * 18
            for k in Swift.max(k0 - 1, 0) ... Swift.min(k0 + 1, nz - 1) {
                for j in Swift.max(j0 - 1, 0) ... Swift.min(j0 + 1, ny - 1) {
                    // The cubes of one row are consecutive in the sorted order, so
                    // the run reaches from the first one present to the last.
                    var first = -1, last = -1
                    for i in Swift.max(i0 - 1, 0) ... Swift.min(i0 + 1, nx - 1) {
                        let found = cube(i, j, k)
                        if found >= 0 {
                            if first < 0 { first = found }
                            last = found
                        }
                    }
                    if first >= 0 {
                        runs[r] = starts[first]
                        runs[r + 1] = starts[last + 1]
                    }
                    r += 2
                }
            }
        }

        self.points = points
        self.original = order
        self.cell = cell
        self.runs = runs
    }
}

/// Reorders `order` by `keys[order[n]]`, each key in `0 ..< bound`, keeping
/// equal keys in the order they had: a radix sort, eleven bits a pass.
private func sortStably(_ order: inout [Int32], by keys: [Int], below bound: Int) {
    let n = order.count
    guard n > 1, bound > 1 else { return }
    var spare = [Int32](repeating: 0, count: n)
    var counts = [Int](repeating: 0, count: 2049)
    var shift = 0
    while shift < Int.bitWidth - 1, (bound - 1) >> shift > 0 {
        for b in 0 ... 2048 { counts[b] = 0 }
        for s in 0 ..< n { counts[((keys[Int(order[s])] >> shift) & 2047) + 1] += 1 }
        for b in 1 ... 2048 { counts[b] += counts[b - 1] }
        for s in 0 ..< n {
            let digit = (keys[Int(order[s])] >> shift) & 2047
            spare[counts[digit]] = order[s]
            counts[digit] += 1
        }
        swap(&order, &spare)
        shift += 11
    }
}

/// A heaviest-first queue holding one entry per point still in play. A point's
/// entry is not touched when it grows lighter; it is only found out when it
/// reaches the top, and goes back in at its true weight then. Weights only ever
/// fall, so an entry is never lighter than its point, and a top entry that is
/// still true is the heaviest point there is. Equal weights go by input order,
/// the later point first, so a run repeats exactly.
///
/// Four children to a node keep the walk down short.
private struct ThinningQueue {

    struct Entry {
        var weight: Double
        var sample: Int32
        var original: Int32
    }

    private var entries: [Entry]

    init(weights: UnsafeMutableBufferPointer<Double>, original: [Int32]) {
        entries = (0 ..< weights.count).map {
            Entry(weight: weights[$0], sample: Int32($0), original: original[$0])
        }
        if entries.count > 1 {
            var node = (entries.count - 2) / 4
            while node >= 0 { sink(node); node -= 1 }
        }
    }

    var top: Entry { entries[0] }

    mutating func lowerTop(to weight: Double) {
        entries[0].weight = weight
        sink(0)
    }

    mutating func removeTop() {
        let last = entries.removeLast()
        if !entries.isEmpty {
            entries[0] = last
            sink(0)
        }
    }

    @inline(__always)
    private static func heavier(_ a: Entry, _ b: Entry) -> Bool {
        a.weight > b.weight || (a.weight == b.weight && a.original > b.original)
    }

    private mutating func sink(_ start: Int) {
        entries.withUnsafeMutableBufferPointer { e in
            let n = e.count
            let moving = e[start]
            var node = start
            while true {
                let first = 4 * node + 1
                if first >= n { break }
                var child = first
                var next = first + 1
                let end = Swift.min(first + 4, n)
                while next < end {
                    if Self.heavier(e[next], e[child]) { child = next }
                    next += 1
                }
                guard Self.heavier(e[child], moving) else { break }
                e[node] = e[child]
                node = child
            }
            e[node] = moving
        }
    }
}
