import Foundation

/// Spanning-tree drawing: connect a set of points with the shortest total
/// line work that still reaches every one of them, the branching sibling of
/// the single-line tour. Stipple a picture, span the dots, and the tree
/// reads as the picture drawn in veins: dark regions thicken into dense
/// capillary tangles, light regions carry only the few trunks passing
/// through. Where the tour is one unbroken meander, the tree branches, so
/// the same dots come out organic rather than labyrinthine.
///
/// ```swift
/// let dots = stipple(picture, count: 4000, in: frame)
/// for chain in spanningTree(through: dots) {
///     drawPolyline(chain.points)
/// }
/// ```
///
/// The result is the Euclidean minimum spanning tree, decomposed into as few
/// polyline chains as the tree's branching allows, so the output is a small
/// set of long strokes rather than a segment soup: friendly to a pen plotter
/// (each chain is one pen-down run) and to `drawPolyline`/SVG export alike.
/// Deterministic given the points, and setup-time-shaped: span once and
/// hold the result.

/// The minimum spanning tree of `points`, returned as open polyline chains
/// that together draw every tree edge exactly once. The tree is exact (built
/// on the Delaunay triangulation, which always contains it), and the chain
/// decomposition is minimal: one chain per pair of odd-degree vertices.
/// Deterministic. Comfortable at tens of thousands of points.
public func spanningTree(through points: [Vector2]) -> [Contour] {
    let n = points.count
    guard n >= 2 else { return [] }

    // Candidate edges: the unique edges of the Delaunay triangulation, which
    // is guaranteed to contain the Euclidean MST. Fully collinear input has
    // no triangulation; there the tree is simply the points chained in order
    // along their line, which lexicographic order walks exactly.
    let delaunay = Delaunay(points)
    var seen = Set<UInt64>()
    var edges: [(a: Int, b: Int, d2: Double)] = []
    func addEdge(_ x: Int, _ y: Int) {
        let lo = min(x, y), hi = max(x, y)
        let key = UInt64(lo) << 32 | UInt64(hi)
        if seen.insert(key).inserted {
            edges.append((lo, hi, points[lo].distanceSquared(to: points[hi])))
        }
    }
    var k = 0
    while k + 2 < delaunay.indices.count {
        let a = delaunay.indices[k], b = delaunay.indices[k + 1], c = delaunay.indices[k + 2]
        addEdge(a, b)
        addEdge(b, c)
        addEdge(c, a)
        k += 3
    }
    if edges.isEmpty {
        let order = points.indices.sorted {
            points[$0].x != points[$1].x ? points[$0].x < points[$1].x
                : (points[$0].y != points[$1].y ? points[$0].y < points[$1].y : $0 < $1)
        }
        return [Contour(order.map { points[$0] }, closed: false)]
    }

    // Kruskal with a deterministic tie-break: shortest edge first, index
    // order among equals, joined through union-find.
    edges.sort { $0.d2 != $1.d2 ? $0.d2 < $1.d2
        : ($0.a != $1.a ? $0.a < $1.a : $0.b < $1.b) }
    var parent = Array(0 ..< n)
    var rank = [Int](repeating: 0, count: n)
    func find(_ x: Int) -> Int {
        var root = x
        while parent[root] != root { root = parent[root] }
        var cur = x
        while parent[cur] != root { let next = parent[cur]; parent[cur] = root; cur = next }
        return root
    }
    func union(_ x: Int, _ y: Int) {
        let rx = find(x), ry = find(y)
        guard rx != ry else { return }
        if rank[rx] < rank[ry] { parent[rx] = ry }
        else if rank[rx] > rank[ry] { parent[ry] = rx }
        else { parent[ry] = rx; rank[rx] += 1 }
    }

    var tree: [(Int, Int)] = []
    tree.reserveCapacity(n - 1)
    for e in edges where find(e.a) != find(e.b) {
        union(e.a, e.b)
        tree.append((e.a, e.b))
    }

    // Exactly-coincident duplicates never enter the triangulation, so they
    // can be left behind as isolated vertices; stitch each remaining
    // component to its nearest vertex outside it. Degenerate inputs only.
    for v in 0 ..< n where find(v) != find(0) {
        while find(v) != find(0) {
            var best = -1
            var bestDistance = Double.infinity
            for u in 0 ..< n where find(u) != find(v) {
                let d = points[u].distanceSquared(to: points[v])
                if d < bestDistance || (d == bestDistance && u < best) {
                    bestDistance = d
                    best = u
                }
            }
            guard best >= 0 else { break }
            union(v, best)
            tree.append((min(v, best), max(v, best)))
        }
    }

    // Decompose the tree into chains: every trail must start and end at an
    // odd-degree vertex, and each greedy walk retires two of them, so
    // walking from odd vertices in index order yields the minimal number of
    // chains. Adjacency lists stay sorted so the walk is deterministic.
    var adjacency = [[Int]](repeating: [], count: n)
    for (a, b) in tree {
        adjacency[a].append(b)
        adjacency[b].append(a)
    }
    for i in 0 ..< n { adjacency[i].sort() }
    var cursor = [Int](repeating: 0, count: n)   // next unconsumed neighbor
    var remaining = adjacency.map(\.count)       // unconsumed degree
    var consumed = Set<UInt64>()
    func take(from v: Int) -> Int? {
        while cursor[v] < adjacency[v].count {
            let u = adjacency[v][cursor[v]]
            let key = UInt64(min(v, u)) << 32 | UInt64(max(v, u))
            if consumed.contains(key) { cursor[v] += 1; continue }
            consumed.insert(key)
            cursor[v] += 1
            remaining[v] -= 1
            remaining[u] -= 1
            return u
        }
        return nil
    }

    // A walk may only start where the *unconsumed* degree is odd: each walk
    // flips its two endpoints odd-to-even and no vertex ever flips back, so
    // the index-order sweep retires every odd vertex in exactly odd/2 walks
    // and never strands an edge into an extra chain.
    var chains: [Contour] = []
    for start in 0 ..< n where adjacency[start].count % 2 == 1 {
        while remaining[start] % 2 == 1, let first = take(from: start) {
            var walk = [points[start], points[first]]
            var current = first
            while let next = take(from: current) {
                walk.append(points[next])
                current = next
            }
            chains.append(Contour(walk, closed: false))
        }
    }
    return chains
}

// MARK: - Sketch sugar

public extension Sketch {
    /// The spanning-tree rendering of `image`: stipple it with `points` dots,
    /// then join them by the minimum spanning tree, the branching sibling of
    /// `singleLine(of:points:)`. The image is stretched over `bounds` (the
    /// whole canvas by default); pass a `Rectangle(fitting:in:)` of the
    /// image's size to keep its aspect. Driven by the seeded `random`, so
    /// `seed(_:)` reproduces the drawing. Setup-time work: span once and
    /// hold the chains.
    ///
    /// `cutoff` rounds bright grays up to paper, exactly as in
    /// `singleLine(of:points:)`: pixels lighter than it place no dots, so
    /// light regions stay empty instead of collecting stray twigs.
    func spanningTree(of image: Image,
                      points count: Int,
                      in bounds: Rectangle? = nil,
                      iterations: Int = 40,
                      cutoff: Double = 0.85) -> [Contour] {
        let rect = bounds ?? canvasRectangle
        guard image.width > 0, image.height > 0 else { return [] }
        let cutoffLinear = Color.srgbToLinear(Swift.min(Swift.max(cutoff, 0), 1))
        let dots = stipple(count: count, in: rect, iterations: iterations) { p in
            let px = Swift.min(Swift.max(Int((p.x - rect.x) / rect.width * Double(image.width)), 0),
                               image.width - 1)
            let py = Swift.min(Swift.max(Int((p.y - rect.y) / rect.height * Double(image.height)), 0),
                               image.height - 1)
            let c = image[px, py]
            let tone = c.luminance
            guard tone < cutoffLinear else { return 0 }
            return (1 - tone) * c.alpha
        }
        return Ollin.spanningTree(through: dots)
    }
}
