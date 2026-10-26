import Foundation

/// An index over a set of rectangles: the structure that answers "which boxes
/// hold this point", "which boxes overlap this rectangle", and "which boxes
/// overlap each other" without testing every box.
///
/// Where ``SpatialIndex`` holds points, this holds extents. Hand it the bounds
/// of a thousand shapes and picking the one under the pointer reads a few
/// boxes rather than a thousand. Hand it every outline's box and the pairs
/// that could collide come back before any outline is tested against another.
/// Hand it the pieces already placed and a packing asks whether a new one fits.
///
/// ```swift
/// let index = BoundsIndex(shapes.map(\.bounds))
/// if let top = index.indices(containing: mouse).last { highlight(shapes[top]) }
/// for pair in index.overlappingPairs() { test(shapes[pair.first], shapes[pair.second]) }
/// ```
///
/// Every answer is an **index into `boxes`**, so a sketch keeps its own payload
/// beside the boxes and reads it back with the same index. The array-returning
/// queries answer ascending by index, and a pair lists its lower index first.
///
/// ## How it is arranged
///
/// A bounding-volume hierarchy. The boxes are cut into two halves at the
/// median of their centers along whichever axis the centers spread over most,
/// each half is cut again, and every node of the tree keeps the one box that
/// holds everything under it. A query walks down only the nodes whose box it
/// reaches, so most boxes are never tested. When the boxes move a little each
/// frame without changing their order, ``refit(to:)`` keeps the tree's shape
/// and recomputes the nodes' boxes from the leaves up, which costs one pass
/// rather than a build.
///
/// ## Exactness
///
/// The boundary counts as inside, matching `Rectangle.contains(_:)` and
/// `Rectangle.intersects(_:)`: a point on an edge is held by that box, and two
/// boxes that share an edge overlap. Every answer equals what a loop over every
/// box would find.
public struct BoundsIndex: Sendable {

    /// Two indices whose boxes overlap. Within one set, `first` is the lower
    /// index. Across two sets, `first` indexes this index's boxes and `second`
    /// the other's.
    public struct Pair: Equatable, Hashable, Sendable {
        public let first: Int
        public let second: Int

        public init(_ first: Int, _ second: Int) {
            self.first = first
            self.second = second
        }
    }

    /// A node of the hierarchy: the box around everything under it, and either
    /// two children or a run of `order`.
    private struct Node {
        var minX: Double, minY: Double, maxX: Double, maxY: Double
        var left: Int32       // -1 for a leaf
        var right: Int32
        var lo: Int32         // the leaf's run in `order`
        var hi: Int32
    }

    /// How many boxes a leaf holds before it is cut. A short run a query scans
    /// straight through beats a deeper tree, because the descent costs more
    /// than the few tests it saves.
    private static let leafSize = 4

    /// The boxes the index was built over, in the order they were given.
    public private(set) var boxes: [Rectangle]

    /// Nodes in the order they were made, each before its children, so a walk
    /// from the last node to the first sees every child before its parent.
    private var nodes: [Node]
    /// Box indices, permuted so that every leaf owns one run of this array.
    private var order: [Int32]
    private var root: Int32

    // MARK: - Building

    /// An index over `boxes`.
    public init(_ boxes: [Rectangle]) {
        self.boxes = boxes
        order = (0 ..< Int32(boxes.count)).map { $0 }
        nodes = []
        root = -1
        guard !boxes.isEmpty else { return }
        nodes.reserveCapacity(2 * (boxes.count / BoundsIndex.leafSize + 1))
        root = build(0, boxes.count)
    }

    /// How many boxes the index holds.
    public var count: Int { boxes.count }

    /// Whether the index holds no boxes.
    public var isEmpty: Bool { boxes.isEmpty }

    /// The one rectangle around every box, or nil when the index is empty.
    public var bounds: Rectangle? {
        guard root >= 0 else { return nil }
        let node = nodes[Int(root)]
        guard node.minX <= node.maxX, node.minY <= node.maxY else { return nil }
        return Rectangle(x: node.minX, y: node.minY,
                         width: node.maxX - node.minX, height: node.maxY - node.minY)
    }

    /// Replace every box with its moved form and keep the tree's shape.
    ///
    /// The new array has to hold the boxes in the same order as the old one:
    /// box `i` is still the `i`-th box, only placed elsewhere. The nodes' boxes
    /// are recomputed from the leaves up, one pass over the tree, which is the
    /// cheap road for boxes that drift a little each frame. Boxes that have
    /// moved far from where they were built still answer exactly, only slower,
    /// because the nodes' boxes grow to hold them; a changed count rebuilds.
    public mutating func refit(to moved: [Rectangle]) {
        guard moved.count == boxes.count, root >= 0 else {
            self = BoundsIndex(moved)
            return
        }
        boxes = moved
        var n = nodes.count - 1
        while n >= 0 {
            if nodes[n].left < 0 {
                fitLeaf(n)
            } else {
                let l = nodes[Int(nodes[n].left)], r = nodes[Int(nodes[n].right)]
                nodes[n].minX = Swift.min(l.minX, r.minX); nodes[n].maxX = Swift.max(l.maxX, r.maxX)
                nodes[n].minY = Swift.min(l.minY, r.minY); nodes[n].maxY = Swift.max(l.maxY, r.maxY)
            }
            n -= 1
        }
    }

    /// Build the node over `order[lo ..< hi]` and everything under it. The
    /// recursion is bounded by the median split: each level halves the run, so
    /// the depth is the logarithm of the count whatever the boxes are.
    private mutating func build(_ lo: Int, _ hi: Int) -> Int32 {
        let index = Int32(nodes.count)
        nodes.append(Node(minX: 0, minY: 0, maxX: 0, maxY: 0,
                          left: -1, right: -1, lo: Int32(lo), hi: Int32(hi)))
        guard hi - lo > BoundsIndex.leafSize else {
            fitLeaf(Int(index))
            return index
        }
        // Cut along the axis the centers spread over most, the choice that
        // keeps the two halves' boxes as small and as separate as it can.
        var loX = Double.infinity, hiX = -Double.infinity
        var loY = Double.infinity, hiY = -Double.infinity
        for k in lo ..< hi {
            let c = boxes[Int(order[k])].center
            if c.x < loX { loX = c.x }; if c.x > hiX { hiX = c.x }
            if c.y < loY { loY = c.y }; if c.y > hiY { hiY = c.y }
        }
        let axis = (hiX - loX) >= (hiY - loY) ? 0 : 1
        let mid = (lo + hi) / 2
        BoundsIndex.select(&order, lo, hi, mid) { entry in
            let c = boxes[Int(entry)].center
            return axis == 0 ? c.x : c.y
        }
        let left = build(lo, mid)
        let right = build(mid, hi)
        let l = nodes[Int(left)], r = nodes[Int(right)]
        nodes[Int(index)].left = left
        nodes[Int(index)].right = right
        nodes[Int(index)].minX = Swift.min(l.minX, r.minX); nodes[Int(index)].maxX = Swift.max(l.maxX, r.maxX)
        nodes[Int(index)].minY = Swift.min(l.minY, r.minY); nodes[Int(index)].maxY = Swift.max(l.maxY, r.maxY)
        return index
    }

    /// The box around a leaf's run, found by comparison so that a box with a
    /// coordinate that is not a number contributes nothing rather than
    /// poisoning the node.
    private mutating func fitLeaf(_ n: Int) {
        var loX = Double.infinity, hiX = -Double.infinity
        var loY = Double.infinity, hiY = -Double.infinity
        for k in nodes[n].lo ..< nodes[n].hi {
            let b = boxes[Int(order[Int(k)])]
            let x1 = b.x + b.width, y1 = b.y + b.height
            if b.x < loX { loX = b.x }; if x1 > hiX { hiX = x1 }
            if b.y < loY { loY = b.y }; if y1 > hiY { hiY = y1 }
        }
        nodes[n].minX = loX; nodes[n].maxX = hiX
        nodes[n].minY = loY; nodes[n].maxY = hiY
    }

    /// Rearrange `order[lo ..< hi]` so that the entry at `k` is the one that
    /// belongs there by `key`, everything before it is not greater, and
    /// everything after is not smaller: the two-sided partition loop, which
    /// walks past equal keys from both ends and so cannot stall on a set of
    /// boxes stacked on one spot.
    private static func select(_ order: inout [Int32], _ lo: Int, _ hi: Int,
                               _ k: Int, _ key: (Int32) -> Double) {
        var left = lo, right = hi - 1
        while left < right {
            let pivot = key(order[(left + right) / 2])
            var i = left, j = right
            while i <= j {
                while key(order[i]) < pivot { i += 1 }
                while key(order[j]) > pivot { j -= 1 }
                if i <= j { order.swapAt(i, j); i += 1; j -= 1 }
            }
            if k <= j { right = j } else if k >= i { left = i } else { return }
        }
    }

    // MARK: - Queries

    /// The indices of every box that holds `point`, ascending by index. The
    /// boundary counts as inside. For picking, the last one is the box drawn
    /// last, the one on top.
    public func indices(containing point: Vector2) -> [Int] {
        var found: [Int] = []
        forEachIndex(containing: point) { found.append($0) }
        found.sort()
        return found
    }

    /// The indices of every box that overlaps `region`, ascending by index.
    /// Boxes that only touch it count.
    public func indices(overlapping region: Rectangle) -> [Int] {
        var found: [Int] = []
        forEachIndex(overlapping: region) { found.append($0) }
        found.sort()
        return found
    }

    /// Visit every box that holds `point` without building the answer array,
    /// in the index's own fixed walk order.
    public func forEachIndex(containing point: Vector2, _ body: (Int) -> Void) {
        guard root >= 0 else { return }
        let px = point.x, py = point.y
        var stack: [Int32] = []
        stack.reserveCapacity(64)
        stack.append(root)
        while let n = stack.popLast() {
            let node = nodes[Int(n)]
            guard px >= node.minX, px <= node.maxX, py >= node.minY, py <= node.maxY else { continue }
            if node.left < 0 {
                for k in node.lo ..< node.hi {
                    let i = Int(order[Int(k)])
                    if boxes[i].contains(point) { body(i) }
                }
            } else {
                stack.append(node.right)
                stack.append(node.left)
            }
        }
    }

    /// Visit every box that overlaps `region` without building the answer
    /// array, in the index's own fixed walk order.
    public func forEachIndex(overlapping region: Rectangle, _ body: (Int) -> Void) {
        guard root >= 0 else { return }
        let x0 = region.x, y0 = region.y, x1 = region.x + region.width, y1 = region.y + region.height
        var stack: [Int32] = []
        stack.reserveCapacity(64)
        stack.append(root)
        while let n = stack.popLast() {
            let node = nodes[Int(n)]
            guard node.minX <= x1, x0 <= node.maxX, node.minY <= y1, y0 <= node.maxY else { continue }
            if node.left < 0 {
                for k in node.lo ..< node.hi {
                    let i = Int(order[Int(k)])
                    if boxes[i].intersects(region) { body(i) }
                }
            } else {
                stack.append(node.right)
                stack.append(node.left)
            }
        }
    }

    /// Every pair of boxes in this index that overlap each other, each pair
    /// once with its lower index first, ascending by the first index and then
    /// the second. Boxes that only touch count.
    ///
    /// This is the broad phase: the list of what *could* be touching, found by
    /// walking the tree against itself, so that the exact test (two outlines,
    /// two disks) runs only on these pairs.
    public func overlappingPairs() -> [Pair] {
        guard root >= 0 else { return [] }
        var pairs: [Pair] = []
        var stack: [(Int32, Int32)] = []
        stack.reserveCapacity(128)
        stack.append((root, root))
        while let (a, b) = stack.popLast() {
            let na = nodes[Int(a)], nb = nodes[Int(b)]
            if a == b {
                if na.left < 0 {
                    for k in na.lo ..< na.hi {
                        let i = Int(order[Int(k)])
                        for m in (k + 1) ..< na.hi {
                            let j = Int(order[Int(m)])
                            if boxes[i].intersects(boxes[j]) {
                                pairs.append(Pair(Swift.min(i, j), Swift.max(i, j)))
                            }
                        }
                    }
                } else {
                    stack.append((na.left, na.left))
                    stack.append((na.right, na.right))
                    stack.append((na.left, na.right))
                }
                continue
            }
            guard na.minX <= nb.maxX, nb.minX <= na.maxX,
                  na.minY <= nb.maxY, nb.minY <= na.maxY else { continue }
            if na.left < 0, nb.left < 0 {
                for k in na.lo ..< na.hi {
                    let i = Int(order[Int(k)])
                    for m in nb.lo ..< nb.hi {
                        let j = Int(order[Int(m)])
                        if boxes[i].intersects(boxes[j]) {
                            pairs.append(Pair(Swift.min(i, j), Swift.max(i, j)))
                        }
                    }
                }
            } else if na.left < 0 {
                stack.append((a, nb.left)); stack.append((a, nb.right))
            } else if nb.left < 0 {
                stack.append((na.left, b)); stack.append((na.right, b))
            } else {
                stack.append((na.left, nb.left)); stack.append((na.left, nb.right))
                stack.append((na.right, nb.left)); stack.append((na.right, nb.right))
            }
        }
        pairs.sort { $0.first != $1.first ? $0.first < $1.first : $0.second < $1.second }
        return pairs
    }

    /// Every pair of a box in this index and a box in `other` that overlap,
    /// `first` indexing this index's boxes and `second` the other's, ascending
    /// by the first index and then the second. Boxes that only touch count.
    public func overlappingPairs(with other: BoundsIndex) -> [Pair] {
        guard root >= 0, other.root >= 0 else { return [] }
        var pairs: [Pair] = []
        var stack: [(Int32, Int32)] = []
        stack.reserveCapacity(128)
        stack.append((root, other.root))
        while let (a, b) = stack.popLast() {
            let na = nodes[Int(a)], nb = other.nodes[Int(b)]
            guard na.minX <= nb.maxX, nb.minX <= na.maxX,
                  na.minY <= nb.maxY, nb.minY <= na.maxY else { continue }
            if na.left < 0, nb.left < 0 {
                for k in na.lo ..< na.hi {
                    let i = Int(order[Int(k)])
                    for m in nb.lo ..< nb.hi {
                        let j = Int(other.order[Int(m)])
                        if boxes[i].intersects(other.boxes[j]) { pairs.append(Pair(i, j)) }
                    }
                }
            } else if na.left < 0 {
                stack.append((a, nb.left)); stack.append((a, nb.right))
            } else if nb.left < 0 {
                stack.append((na.left, b)); stack.append((na.right, b))
            } else {
                stack.append((na.left, nb.left)); stack.append((na.left, nb.right))
                stack.append((na.right, nb.left)); stack.append((na.right, nb.right))
            }
        }
        pairs.sort { $0.first != $1.first ? $0.first < $1.first : $0.second < $1.second }
        return pairs
    }
}
