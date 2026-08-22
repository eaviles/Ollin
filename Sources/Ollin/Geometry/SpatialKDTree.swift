import Foundation

/// The tree half of ``SpatialIndex``: a k-d tree over 2D points, which is the
/// arrangement that keeps its speed when the points are gathered into clumps
/// with wide empty space between them.
///
/// The set is cut in half along whichever axis it is widest on, and each half is
/// cut again, until a part holds few enough points to scan. A search walks down
/// the side the query point falls on, then reads the other side only when the
/// ball around the best find so far crosses the cut. That crossing test is the
/// whole idea: it is what lets the search skip a subtree instead of measuring it.
///
/// Nodes and point order live in flat arrays rather than linked objects, so a
/// build allocates twice and a search chases no pointers.
struct KDTree2 {

    /// A cut, or a bucket of points when `axis` is negative.
    private struct Node {
        var axis: Int8
        var split: Double
        var lo: Int32
        var hi: Int32
        var left: Int32
        var right: Int32
    }

    /// The point count under which a part stops being cut. A bucket that a
    /// search scans straight through beats a deeper tree, because the descent
    /// costs more than the few distance measurements it saves.
    private static let bucketSize = 12

    private let xs: [Double], ys: [Double]
    /// Point indices, permuted so that every node owns one run of this array.
    private var order: [Int32]
    private var nodes: [Node]
    private let root: Int32

    init(points: [Vector2]) {
        var xs = [Double](repeating: 0, count: points.count)
        var ys = xs
        for i in points.indices { xs[i] = points[i].x; ys[i] = points[i].y }
        self.xs = xs
        self.ys = ys
        order = (0 ..< Int32(points.count)).map { $0 }
        nodes = []
        guard !points.isEmpty else { root = -1; return }
        nodes.reserveCapacity(2 * (points.count / KDTree2.bucketSize + 1))
        root = KDTree2.build(0, points.count, xs, ys, &order, &nodes)
    }

    // MARK: - Building

    private static func build(_ lo: Int, _ hi: Int, _ xs: [Double], _ ys: [Double],
                              _ order: inout [Int32], _ nodes: inout [Node]) -> Int32 {
        let index = Int32(nodes.count)
        nodes.append(Node(axis: -1, split: 0, lo: Int32(lo), hi: Int32(hi),
                          left: -1, right: -1))
        guard hi - lo > bucketSize else { return index }

        // Cut along the axis the points spread over most, which is the choice
        // that makes the parts as square as possible and the crossing test as
        // strong as possible.
        var loX = Double.infinity, hiX = -Double.infinity
        var loY = Double.infinity, hiY = -Double.infinity
        for k in lo ..< hi {
            let p = Int(order[k])
            if xs[p] < loX { loX = xs[p] }; if xs[p] > hiX { hiX = xs[p] }
            if ys[p] < loY { loY = ys[p] }; if ys[p] > hiY { hiY = ys[p] }
        }
        let axis: Int8 = (hiX - loX) >= (hiY - loY) ? 0 : 1
        let mid = (lo + hi) / 2
        select(&order, lo, hi, mid, axis, xs, ys)
        let split = axis == 0 ? xs[Int(order[mid])] : ys[Int(order[mid])]

        let left = build(lo, mid, xs, ys, &order, &nodes)
        let right = build(mid, hi, xs, ys, &order, &nodes)
        nodes[Int(index)].axis = axis
        nodes[Int(index)].split = split
        nodes[Int(index)].left = left
        nodes[Int(index)].right = right
        return index
    }

    /// Rearrange `order[lo..<hi]` so that the entry at `k` is the one that
    /// belongs there in axis order, everything before it is not greater, and
    /// everything after is not smaller. This is the classic two-sided partition
    /// loop, which walks past equal values from both ends and so cannot stall on
    /// a set with many repeated coordinates.
    private static func select(_ order: inout [Int32], _ lo: Int, _ hi: Int,
                               _ k: Int, _ axis: Int8,
                               _ xs: [Double], _ ys: [Double]) {
        func value(_ entry: Int32) -> Double {
            axis == 0 ? xs[Int(entry)] : ys[Int(entry)]
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

    /// The nearest point, or nil when the tree is empty. Equal distances answer
    /// with the lower index.
    func nearest(to p: Vector2) -> Int? {
        guard root >= 0 else { return nil }
        var best = -1, bestD2 = Double.infinity
        search(Int(root), p) { index, d2 in
            // The first candidate always wins: see the note in `CellGrid`.
            if best < 0 || d2 < bestD2 || (d2 == bestD2 && index < best) {
                bestD2 = d2; best = index
            }
            return bestD2
        }
        return best >= 0 ? best : nil
    }

    /// The `want` nearest points, ascending by distance and then by index.
    func kNearest(_ want: Int, to p: Vector2) -> [Int] {
        guard root >= 0 else { return [] }
        var found: [(d2: Double, i: Int)] = []
        found.reserveCapacity(want)
        search(Int(root), p) { index, d2 in
            // A tie at the far end still has to let the lower index in, so the
            // full list is kept sorted by (distance, index) rather than by
            // distance alone.
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

    /// Walk the tree nearest-side first, reporting every candidate to `consider`,
    /// which answers with the distance the search may now prune at.
    private func search(_ node: Int, _ p: Vector2, _ consider: (Int, Double) -> Double) {
        var bound = Double.infinity
        func visit(_ n: Int) {
            let node = nodes[n]
            if node.axis < 0 {
                for k in node.lo ..< node.hi {
                    let index = Int(order[Int(k)])
                    let dx = xs[index] - p.x, dy = ys[index] - p.y
                    bound = consider(index, dx * dx + dy * dy)
                }
                return
            }
            let along = node.axis == 0 ? p.x : p.y
            let diff = along - node.split
            let near = diff < 0 ? node.left : node.right
            let far = diff < 0 ? node.right : node.left
            visit(Int(near))
            // The far side can still hold a tie, so the crossing test lets an
            // exactly-equal distance through rather than pruning it.
            if diff * diff <= bound { visit(Int(far)) }
        }
        visit(node)
    }

    func forNeighbors(of p: Vector2, within radius: Double, skipping: Int,
                      _ body: (Int, Double) -> Void) {
        guard root >= 0 else { return }
        let r2 = radius * radius
        func visit(_ n: Int) {
            let node = nodes[n]
            if node.axis < 0 {
                for k in node.lo ..< node.hi {
                    let index = Int(order[Int(k)])
                    if index == skipping { continue }
                    let dx = xs[index] - p.x, dy = ys[index] - p.y
                    let d2 = dx * dx + dy * dy
                    if d2 <= r2 { body(index, d2) }
                }
                return
            }
            let along = node.axis == 0 ? p.x : p.y
            let diff = along - node.split
            if diff <= 0 || diff * diff <= r2 { visit(Int(node.left)) }
            if diff >= 0 || diff * diff <= r2 { visit(Int(node.right)) }
        }
        visit(Int(root))
    }

    func anyNeighbor(of p: Vector2, within radius: Double, skipping: Int) -> Int? {
        guard root >= 0 else { return nil }
        let r2 = radius * radius
        func visit(_ n: Int) -> Int? {
            let node = nodes[n]
            if node.axis < 0 {
                for k in node.lo ..< node.hi {
                    let index = Int(order[Int(k)])
                    if index == skipping { continue }
                    let dx = xs[index] - p.x, dy = ys[index] - p.y
                    if dx * dx + dy * dy <= r2 { return index }
                }
                return nil
            }
            let along = node.axis == 0 ? p.x : p.y
            let diff = along - node.split
            let near = diff < 0 ? node.left : node.right
            let far = diff < 0 ? node.right : node.left
            if let hit = visit(Int(near)) { return hit }
            if diff * diff <= r2 { return visit(Int(far)) }
            return nil
        }
        return visit(Int(root))
    }

    func forPoints(in region: Rectangle, _ body: (Int) -> Void) {
        guard root >= 0 else { return }
        let loX = region.x, loY = region.y
        let hiX = region.x + region.width, hiY = region.y + region.height
        func visit(_ n: Int) {
            let node = nodes[n]
            if node.axis < 0 {
                for k in node.lo ..< node.hi {
                    let index = Int(order[Int(k)])
                    let x = xs[index], y = ys[index]
                    if x >= loX, x <= hiX, y >= loY, y <= hiY { body(index) }
                }
                return
            }
            let lo = node.axis == 0 ? loX : loY
            let hi = node.axis == 0 ? hiX : hiY
            if lo <= node.split { visit(Int(node.left)) }
            if hi >= node.split { visit(Int(node.right)) }
        }
        visit(Int(root))
    }
}
