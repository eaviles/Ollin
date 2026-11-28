import Foundation
import Ollin

/// One relaxation pass over the colliding disks of a `World`: which pairs can
/// touch, and the push that separates the ones that do.
///
/// The disks are gathered into one array for the pass and written back after
/// it, so the inner loop reads plain numbers rather than objects. Finding the
/// pairs is a grid of several cell sizes held in one flat table:
///
/// - **A level for each size.** The coarsest cell is as wide as the largest
///   disk, and each level under it halves the cell. A disk is filed once, by
///   its center, at the finest level whose cell is still at least as wide as
///   the disk. Two disks of one level can only touch from the same or a
///   neighboring cell, and a small disk can only touch a larger one filed in
///   the few cells around the small one's place at the larger one's level.
///   So a disk looks at its own level and at each coarser level that holds
///   anything, and the cost of a small disk no longer depends on how large
///   the largest one is.
/// - **One table.** Every (level, cell) is hashed into a table of buckets
///   that is filled by a counting sort: count the disks of each bucket, turn
///   the counts into offsets, and drop each disk's index into one contiguous
///   array. Nothing is allocated per cell, and the arrays are kept between
///   passes.
///
/// Two cells can share a bucket, and so can two levels, so a disk found in a
/// bucket is taken only when the cell and the level it was filed under are the
/// ones being looked in.
///
/// The order is fixed: disks are walked by index, the nine cells in one scan
/// order, a bucket's disks by index. Resolving a pair moves both disks, so the
/// order decides the outcome, and a fixed one is what makes a seeded pile
/// settle the same on every run. When every disk is within a factor of two of
/// the largest there is one level, and the pairs and their order are the ones
/// a single grid of the largest disk's width gives.
struct DiskPass {

    /// One colliding disk, as the pass sees it.
    struct Disk {
        var x: Double
        var y: Double
        var radius: Double
        /// The share of a push this disk takes: its inverse mass, or zero
        /// when it is pinned.
        var weight: Double
        /// The cell it was filed under, at its own level.
        var cellX: Int64 = 0
        var cellY: Int64 = 0
        var level: Int32 = 0
        /// Its place in the world's `particles`.
        var index: Int32
    }

    /// The disks of this pass, in the order they were added.
    private(set) var disks: [Disk] = []
    /// `start[b] ..< start[b + 1]` is bucket `b`'s run in `entries`.
    private var start: [Int32] = []
    /// Disk indices, grouped by bucket, ascending inside each.
    private var entries: [Int32] = []
    /// Bit `k` is set when some disk is filed at level `k`.
    private var levelsUsed: UInt32 = 0
    /// The coarsest cell's width: the largest disk's diameter.
    private var top = 0.0
    private var largestRadius = 0.0
    /// The table holds `1 << tableBits` buckets.
    private(set) var tableBits = 4

    /// The finest level there is. A disk smaller than the largest by more
    /// than this many halvings is filed here anyway, in a cell wider than it
    /// needs, which is slower for it and still finds every pair.
    static let finestLevel = 30

    /// `scale[k]` is `2^k`: how many cells of level `k` span one of level 0.
    private static let scale: [Double] = (0 ... finestLevel).map { Double(sign: .plus, exponent: $0, significand: 1) }

    /// Empty the pass, keeping its storage.
    mutating func removeAll() {
        disks.removeAll(keepingCapacity: true)
        largestRadius = 0
    }

    /// Add a disk. `radius` must be above zero.
    mutating func add(x: Double, y: Double, radius: Double, weight: Double, index: Int) {
        disks.append(Disk(x: x, y: y, radius: radius, weight: weight, index: Int32(truncatingIfNeeded: index)))
        if radius > largestRadius { largestRadius = radius }
    }

    /// The cell a coordinate falls in, as a whole number. A coordinate that
    /// is not a number, or past what a 64-bit count holds, lands on a cell
    /// anyway: such a disk is compared with the wrong neighbors, and nothing
    /// traps.
    @inline(__always)
    private static func cell(_ value: Double) -> Int64 {
        let floor = value.rounded(.down)
        if floor > -4.0e18 && floor < 4.0e18 { return Int64(floor) }
        if floor >= 4.0e18 { return 4_000_000_000_000_000_000 }
        if floor <= -4.0e18 { return -4_000_000_000_000_000_000 }
        return 0
    }

    /// The bucket of a cell at a level: the three primes of the spatial hash
    /// over the cell's coordinates and its level, then the high bits of one
    /// more multiply, which a table whose size is a power of two wants.
    @inline(__always)
    static func bucket(_ level: Int, _ x: Int64, _ y: Int64, bits: Int) -> Int {
        var hash = UInt64(bitPattern: x) &* 73_856_093
        hash ^= UInt64(bitPattern: y) &* 19_349_663
        hash ^= UInt64(truncatingIfNeeded: level) &* 83_492_791
        return Int((hash &* 0x9E37_79B9_7F4A_7C15) >> UInt64(64 - bits))
    }

    /// File every disk under its level and cell, and sort the table.
    mutating func build() {
        let count = disks.count
        top = largestRadius * 2
        levelsUsed = 0
        guard count > 0, top > 0 else { return }

        var bits = 4
        while (1 << bits) < count * 2, bits < 30 { bits += 1 }
        tableBits = bits
        let buckets = 1 << bits
        if start.count != buckets + 1 {
            start = [Int32](repeating: 0, count: buckets + 1)
        } else {
            for b in 0 ... buckets { start[b] = 0 }
        }
        if entries.count != count { entries = [Int32](repeating: 0, count: count) }

        let top = top
        let largest = largestRadius
        var used: UInt32 = 0
        disks.withUnsafeMutableBufferPointer { disks in
            start.withUnsafeMutableBufferPointer { start in
                entries.withUnsafeMutableBufferPointer { entries in
                    for i in 0 ..< count {
                        // How many times the cell can be halved and still span
                        // the disk: the whole part of log2(largest / radius).
                        let halvings = (largest / disks[i].radius).exponent
                        let level = halvings >= DiskPass.finestLevel ? DiskPass.finestLevel : Swift.max(0, halvings)
                        let scale = DiskPass.scale[level]
                        let cx = DiskPass.cell(disks[i].x / top * scale)
                        let cy = DiskPass.cell(disks[i].y / top * scale)
                        disks[i].level = Int32(level)
                        disks[i].cellX = cx
                        disks[i].cellY = cy
                        used |= 1 << UInt32(level)
                        start[DiskPass.bucket(level, cx, cy, bits: bits)] += 1
                    }
                    // Counts into end offsets, then filled from the back, which
                    // leaves each bucket's run starting at its offset with its
                    // disks in ascending order.
                    var running: Int32 = 0
                    for b in 0 ..< buckets {
                        running += start[b]
                        start[b] = running
                    }
                    start[buckets] = running
                    var i = count - 1
                    while i >= 0 {
                        let b = DiskPass.bucket(Int(disks[i].level), disks[i].cellX, disks[i].cellY, bits: bits)
                        start[b] -= 1
                        entries[Int(start[b])] = Int32(i)
                        i -= 1
                    }
                }
            }
        }
        levelsUsed = used
    }

    /// Walk every pair the grid offers, in the pass's order, the lower index
    /// first. `visit` may move the two disks it is handed; the cells a disk
    /// looks in are worked out from where it is when its turn comes, and the
    /// table keeps where every disk was when it was built.
    @inline(__always)
    private mutating func forEachPair(_ visit: (UnsafeMutablePointer<Disk>, Int, Int) -> Void) {
        let count = disks.count
        guard count > 1, top > 0 else { return }
        let top = top, bits = tableBits, used = levelsUsed
        disks.withUnsafeMutableBufferPointer { buffer in
            start.withUnsafeBufferPointer { start in
                entries.withUnsafeBufferPointer { entries in
                    guard let disks = buffer.baseAddress else { return }
                    for i in 0 ..< count {
                        let level = Int(disks[i].level)
                        let qx = disks[i].x / top, qy = disks[i].y / top

                        // Its own level: each pair once, from the lower index.
                        let scale = DiskPass.scale[level]
                        let cx = DiskPass.cell(qx * scale), cy = DiskPass.cell(qy * scale)
                        var dx: Int64 = -1
                        while dx <= 1 {
                            var dy: Int64 = -1
                            while dy <= 1 {
                                let tx = cx &+ dx, ty = cy &+ dy
                                let b = DiskPass.bucket(level, tx, ty, bits: bits)
                                var e = Int(start[b])
                                let end = Int(start[b + 1])
                                while e < end {
                                    let j = Int(entries[e])
                                    e += 1
                                    if j > i, disks[j].cellX == tx, disks[j].cellY == ty, Int(disks[j].level) == level {
                                        visit(disks, i, j)
                                    }
                                }
                                dy += 1
                            }
                            dx += 1
                        }

                        // Every coarser level that holds a disk, coarsest first.
                        // A disk filed there is at most half its cell across,
                        // so only the cells within this disk's radius plus
                        // half a cell of its center can hold one that touches
                        // it: two cells an axis for a disk much smaller than
                        // the cell, never more than three.
                        let reach = disks[i].radius / top
                        var coarser = used & ((1 << UInt32(level)) &- 1)
                        while coarser != 0 {
                            let k = coarser.trailingZeroBitCount
                            coarser &= coarser &- 1
                            let scale = DiskPass.scale[k]
                            let span = (reach * scale + 0.5) * 1.000001
                            let fx = qx * scale, fy = qy * scale
                            let x0 = DiskPass.cell(fx - span), y0 = DiskPass.cell(fy - span)
                            let x1 = Swift.min(DiskPass.cell(fx + span), x0 &+ 2)
                            let y1 = Swift.min(DiskPass.cell(fy + span), y0 &+ 2)
                            var tx = x0
                            while tx <= x1 {
                                var ty = y0
                                while ty <= y1 {
                                    let b = DiskPass.bucket(k, tx, ty, bits: bits)
                                    var e = Int(start[b])
                                    let end = Int(start[b + 1])
                                    while e < end {
                                        let j = Int(entries[e])
                                        e += 1
                                        if disks[j].cellX == tx, disks[j].cellY == ty, Int(disks[j].level) == k {
                                            if j > i { visit(disks, i, j) } else { visit(disks, j, i) }
                                        }
                                    }
                                    ty += 1
                                }
                                tx += 1
                            }
                        }
                    }
                }
            }
        }
    }

    /// Push every overlapping pair apart, each disk by its share of the
    /// overlap. Call `build()` first.
    mutating func resolve() {
        forEachPair { disks, i, j in
            let minDistance = disks[i].radius + disks[j].radius
            let dx = disks[j].x - disks[i].x, dy = disks[j].y - disks[i].y
            let distanceSquared = dx * dx + dy * dy
            guard distanceSquared < minDistance * minDistance else { return }
            let wA = disks[i].weight, wB = disks[j].weight
            let wSum = wA + wB
            guard wSum > 0 else { return }

            // Almost-coincident disks have no reliable normal; shove them
            // apart along x so they separate rather than stay locked together.
            let distance = distanceSquared.squareRoot()
            let nx = distance > 1e-9 ? dx / distance : 1
            let ny = distance > 1e-9 ? dy / distance : 0
            let overlap = minDistance - distance
            let shareA = overlap * (wA / wSum), shareB = overlap * (wB / wSum)
            disks[i].x -= nx * shareA
            disks[i].y -= ny * shareA
            disks[j].x += nx * shareB
            disks[j].y += ny * shareB
        }
    }

    /// Every pair the grid offers, in order, with nothing moved: what the
    /// tests hold against a comparison of every disk with every other.
    mutating func candidatePairs() -> [(Int, Int)] {
        var pairs: [(Int, Int)] = []
        forEachPair { _, i, j in pairs.append((i, j)) }
        return pairs
    }
}
