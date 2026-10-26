import Foundation

/// The tree half of ``SpatialIndex3D``: a k-d tree over points in space, the
/// twin of the flat index's `KDTree2` with a third coordinate and a third axis
/// to cut on.
///
/// The set is cut in half along whichever axis it is widest on, and each half is
/// cut again, until a part holds few enough points to scan. A search walks down
/// the side the query point falls on, then reads the other side only when the
/// ball around the best find so far crosses the cut. Nodes and point order live
/// in flat arrays, so a build allocates twice and a search chases no pointers.
struct KDTree3 {

    /// A cut, or a bucket of points when `axis` is negative.
    private struct Node {
        var axis: Int8
        var split: Double
        var lo: Int32
        var hi: Int32
        var left: Int32
        var right: Int32
    }

    /// The point count under which a part stops being cut.
    private static let bucketSize = 12

    private let xs: [Double], ys: [Double], zs: [Double]
    /// Point indices, permuted so that every node owns one run of this array.
    private var order: [Int32]
    private var nodes: [Node]
    private let root: Int32

    init(points: [Vector3]) {
        var xs = [Double](repeating: 0, count: points.count)
        var ys = xs, zs = xs
        for i in points.indices { xs[i] = points[i].x; ys[i] = points[i].y; zs[i] = points[i].z }
        self.xs = xs
        self.ys = ys
        self.zs = zs
        order = (0 ..< Int32(points.count)).map { $0 }
        nodes = []
        guard !points.isEmpty else { root = -1; return }
        nodes.reserveCapacity(2 * (points.count / KDTree3.bucketSize + 1))
        root = KDTree3.build(0, points.count, xs, ys, zs, &order, &nodes)
    }

    // MARK: - Building

    /// Bounded recursion: each level halves the run at its median, so the
    /// depth is the logarithm of the count whatever the points are.
    private static func build(_ lo: Int, _ hi: Int, _ xs: [Double], _ ys: [Double],
                              _ zs: [Double], _ order: inout [Int32],
                              _ nodes: inout [Node]) -> Int32 {
        let index = Int32(nodes.count)
        nodes.append(Node(axis: -1, split: 0, lo: Int32(lo), hi: Int32(hi),
                          left: -1, right: -1))
        guard hi - lo > bucketSize else { return index }

        var loX = Double.infinity, hiX = -Double.infinity
        var loY = Double.infinity, hiY = -Double.infinity
        var loZ = Double.infinity, hiZ = -Double.infinity
        for k in lo ..< hi {
            let p = Int(order[k])
            if xs[p] < loX { loX = xs[p] }; if xs[p] > hiX { hiX = xs[p] }
            if ys[p] < loY { loY = ys[p] }; if ys[p] > hiY { hiY = ys[p] }
            if zs[p] < loZ { loZ = zs[p] }; if zs[p] > hiZ { hiZ = zs[p] }
        }
        let spanX = hiX - loX, spanY = hiY - loY, spanZ = hiZ - loZ
        let axis: Int8 = spanX >= spanY && spanX >= spanZ ? 0 : (spanY >= spanZ ? 1 : 2)
        let mid = (lo + hi) / 2
        select(&order, lo, hi, mid, axis, xs, ys, zs)
        let at = Int(order[mid])
        let split = axis == 0 ? xs[at] : (axis == 1 ? ys[at] : zs[at])

        let left = build(lo, mid, xs, ys, zs, &order, &nodes)
        let right = build(mid, hi, xs, ys, zs, &order, &nodes)
        nodes[Int(index)].axis = axis
        nodes[Int(index)].split = split
        nodes[Int(index)].left = left
        nodes[Int(index)].right = right
        return index
    }

    /// The two-sided partition loop, which walks past equal values from both
    /// ends and so cannot stall on a set with many repeated coordinates.
    private static func select(_ order: inout [Int32], _ lo: Int, _ hi: Int,
                               _ k: Int, _ axis: Int8,
                               _ xs: [Double], _ ys: [Double], _ zs: [Double]) {
        func value(_ entry: Int32) -> Double {
            let i = Int(entry)
            return axis == 0 ? xs[i] : (axis == 1 ? ys[i] : zs[i])
        }
        var left = lo, right = hi - 1
        while left < right {
            let pivot = value(order[(left + right) / 2])
            var i = left, j = right
            while i <= j {
                while value(order[i]) < pivot { i += 1 }
                while value(order[j]) > pivot { j -= 1 }
                if i <= j { order.swapAt(i, j); i += 1; j -= 1 }
            }
            if k <= j { right = j } else if k >= i { left = i } else { return }
        }
    }

    // MARK: - Queries

    private func coordinate(_ p: Vector3, _ axis: Int8) -> Double {
        axis == 0 ? p.x : (axis == 1 ? p.y : p.z)
    }

    /// The nearest point, or nil when the tree is empty. Equal distances answer
    /// with the lower index.
    func nearest(to p: Vector3) -> Int? {
        guard root >= 0 else { return nil }
        var best = -1, bestD2 = Double.infinity
        search(Int(root), p) { index, d2 in
            if best < 0 || d2 < bestD2 || (d2 == bestD2 && index < best) {
                bestD2 = d2; best = index
            }
            return bestD2
        }
        return best >= 0 ? best : nil
    }

    /// The `want` nearest points, ascending by distance and then by index.
    func kNearest(_ want: Int, to p: Vector3) -> [Int] {
        guard root >= 0 else { return [] }
        var found: [(d2: Double, i: Int)] = []
        found.reserveCapacity(want)
        search(Int(root), p) { index, d2 in
            if found.count == want, let last = found.last,
               d2 > last.d2 || (d2 == last.d2 && index > last.i) {
                return last.d2
            }
            var at = found.count
            while at > 0, found[at - 1].d2 > d2
                    || (found[at - 1].d2 == d2 && found[at - 1].i > index) {
                at -= 1
            }
            found.insert((d2, index), at: at)
            if found.count > want { found.removeLast() }
            return found.count == want ? found[want - 1].d2 : Double.infinity
        }
        return found.map(\.i)
    }

    /// Walk the tree nearest-side first, reporting every candidate to
    /// `consider`, which answers with the distance the search may now prune at.
    private func search(_ node: Int, _ p: Vector3, _ consider: (Int, Double) -> Double) {
        var bound = Double.infinity
        func visit(_ n: Int) {
            let node = nodes[n]
            if node.axis < 0 {
                for k in node.lo ..< node.hi {
                    let index = Int(order[Int(k)])
                    let dx = xs[index] - p.x, dy = ys[index] - p.y, dz = zs[index] - p.z
                    bound = consider(index, dx * dx + dy * dy + dz * dz)
                }
                return
            }
            let diff = coordinate(p, node.axis) - node.split
            let near = diff < 0 ? node.left : node.right
            let far = diff < 0 ? node.right : node.left
            visit(Int(near))
            // The far side can still hold a tie, so an exactly-equal crossing
            // distance is read rather than pruned.
            if diff * diff <= bound { visit(Int(far)) }
        }
        visit(node)
    }

    func forEachNeighbor(of p: Vector3, within radius: Double, skipping: Int,
                         _ body: (Int, Double) -> Void) {
        guard root >= 0 else { return }
        let r2 = radius * radius
        func visit(_ n: Int) {
            let node = nodes[n]
            if node.axis < 0 {
                for k in node.lo ..< node.hi {
                    let index = Int(order[Int(k)])
                    if index == skipping { continue }
                    let dx = xs[index] - p.x, dy = ys[index] - p.y, dz = zs[index] - p.z
                    let d2 = dx * dx + dy * dy + dz * dz
                    if d2 <= r2 { body(index, d2) }
                }
                return
            }
            let diff = coordinate(p, node.axis) - node.split
            if diff <= 0 || diff * diff <= r2 { visit(Int(node.left)) }
            if diff >= 0 || diff * diff <= r2 { visit(Int(node.right)) }
        }
        visit(Int(root))
    }

    func anyNeighbor(of p: Vector3, within radius: Double, skipping: Int) -> Int? {
        guard root >= 0 else { return nil }
        let r2 = radius * radius
        func visit(_ n: Int) -> Int? {
            let node = nodes[n]
            if node.axis < 0 {
                for k in node.lo ..< node.hi {
                    let index = Int(order[Int(k)])
                    if index == skipping { continue }
                    let dx = xs[index] - p.x, dy = ys[index] - p.y, dz = zs[index] - p.z
                    if dx * dx + dy * dy + dz * dz <= r2 { return index }
                }
                return nil
            }
            let diff = coordinate(p, node.axis) - node.split
            let near = diff < 0 ? node.left : node.right
            let far = diff < 0 ? node.right : node.left
            if let hit = visit(Int(near)) { return hit }
            if diff * diff <= r2 { return visit(Int(far)) }
            return nil
        }
        return visit(Int(root))
    }

    func forPoints(in region: Box3, _ body: (Int) -> Void) {
        guard root >= 0 else { return }
        let loX = region.min.x, loY = region.min.y, loZ = region.min.z
        let hiX = region.max.x, hiY = region.max.y, hiZ = region.max.z
        func visit(_ n: Int) {
            let node = nodes[n]
            if node.axis < 0 {
                for k in node.lo ..< node.hi {
                    let index = Int(order[Int(k)])
                    let x = xs[index], y = ys[index], z = zs[index]
                    if x >= loX, x <= hiX, y >= loY, y <= hiY, z >= loZ, z <= hiZ { body(index) }
                }
                return
            }
            let lo = coordinate(region.min, node.axis)
            let hi = coordinate(region.max, node.axis)
            if lo <= node.split { visit(Int(node.left)) }
            if hi >= node.split { visit(Int(node.right)) }
        }
        visit(Int(root))
    }
}
