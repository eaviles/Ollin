import Foundation

/// Concave hulls and alpha shapes: the tighter answers to "what shape are
/// these points?". Where `convexHull(of:)` snaps a rubber band around a
/// scatter, `concaveHull(of:concavity:)` lets the band sink into the gulfs
/// between clusters (still one simple polygon, every point still inside),
/// and `alphaShape(of:alpha:)` rolls a probe disk over the points and keeps
/// only what the disk can't pass through, so the same scatter can come back
/// as several islands with holes.
///
/// ```swift
/// noFill(); stroke(.black)
/// drawPolygon(concaveHull(of: scatter, concavity: 0.7))
/// for island in alphaShape(of: scatter, alpha: 40) {
///     drawShape(island)
/// }
/// ```
///
/// Both are carved out of the Delaunay triangulation, both are deterministic
/// given the points, and both come back as ordinary points and `Shape`s that
/// feed the booleans, hatching, and SVG export.

/// The concave hull of a point set: one simple polygon that follows the
/// scatter's actual outline instead of bridging its gulfs, with every input
/// point inside or on it. `concavity` runs 0...1: 0 is the convex hull, 1
/// hugs the points as tightly as their spacing allows, and values between
/// slide smoothly from one to the other. Returned like `convexHull(of:)`,
/// the boundary points in order, ready to wrap in a `Contour` or `Shape`.
///
/// This is the characteristic-shape construction: erode the Delaunay
/// triangulation's border triangles longest-boundary-edge-first, but never
/// past the point where the boundary would stop being one simple polygon.
/// Deterministic given the points. Degenerate scatters (fewer than three
/// distinct points, or all collinear) fall back to the convex hull.
public func concaveHull(of points: [Vector2], concavity: Double = 0.5) -> [Vector2] {
    var tris = triangleList(of: Delaunay(points))
    guard !tris.isEmpty else { return convexHull(of: points) }
    let n = points.count

    // Edge incidence: for every unique edge, the one or two triangles that
    // own it, plus the edge-length range the concavity knob interpolates
    // over. Built in triangle order; the dictionary is only ever indexed.
    var incidence: [UInt64: (Int, Int)] = [:]
    incidence.reserveCapacity(tris.count * 2)
    var minLength = Double.infinity
    var maxLength = 0.0
    for (t, tri) in tris.enumerated() {
        for (x, y) in [(tri.0, tri.1), (tri.1, tri.2), (tri.2, tri.0)] {
            let key = edgeKey(x, y)
            if let existing = incidence[key] {
                incidence[key] = (existing.0, t)
            } else {
                incidence[key] = (t, -1)
                let length = (points[x] - points[y]).length
                minLength = min(minLength, length)
                maxLength = max(maxLength, length)
            }
        }
    }

    // The erosion's starting boundary must be the convex hull, but the
    // triangulation's finite-precision build can drop a hairline hull
    // sliver, leaving a shallow notch. Cap any missing hull edge with a fan
    // of sliver triangles: zero concavity is then exactly the convex hull,
    // and a cap erodes away like any border triangle once the knob turns.
    capHullNotches(&tris, &incidence, points, &minLength, &maxLength)

    let tightness = min(max(concavity, 0), 1)
    let threshold = maxLength - tightness * (maxLength - minLength)

    // The starting boundary is the convex hull: every edge owned by a single
    // triangle. Longest-first erosion, so the widest bridges cave in first.
    var alive = [Bool](repeating: true, count: tris.count)
    var onBoundary = [Bool](repeating: false, count: n)
    var isBoundaryEdge = Set<UInt64>()
    var heap = EdgeHeap()
    for (_, tri) in tris.enumerated() {
        for (x, y) in [(tri.0, tri.1), (tri.1, tri.2), (tri.2, tri.0)] {
            let key = edgeKey(x, y)
            guard incidence[key]!.1 == -1 else { continue }
            isBoundaryEdge.insert(key)
            onBoundary[x] = true
            onBoundary[y] = true
            heap.push(((points[x] - points[y]).length, key))
        }
    }

    // Erode: a border triangle may go only when its boundary edge is longer
    // than the threshold and its opposite vertex isn't already on the
    // boundary. That single rule is what keeps the polygon simple and every
    // point inside; a blocked edge stays blocked (vertices never leave the
    // boundary), so each edge is considered once.
    while let top = heap.pop() {
        guard top.length > threshold else { break }
        guard isBoundaryEdge.contains(top.key) else { continue }
        let x = Int(top.key >> 32)
        let y = Int(top.key & 0xFFFF_FFFF)
        let (t0, t1) = incidence[top.key]!
        let t = t1 >= 0 && alive[t1] && !alive[t0] ? t1 : t0
        guard alive[t] else { continue }
        let tri = tris[t]
        let v = tri.0 != x && tri.0 != y ? tri.0 : (tri.1 != x && tri.1 != y ? tri.1 : tri.2)
        guard !onBoundary[v] else { continue }

        alive[t] = false
        isBoundaryEdge.remove(top.key)
        onBoundary[v] = true
        for w in [x, y] {
            let key = edgeKey(w, v)
            isBoundaryEdge.insert(key)
            heap.push(((points[w] - points[v]).length, key))
        }
    }

    // Re-derive the boundary from the surviving triangles in triangle order
    // (never walking the working set), then follow it around. Every boundary
    // vertex has exactly two boundary neighbors, so the walk is a single loop.
    var neighborList = [[Int]](repeating: [], count: n)
    var emitted = Set<UInt64>()
    for (t, tri) in tris.enumerated() where alive[t] {
        for (x, y) in [(tri.0, tri.1), (tri.1, tri.2), (tri.2, tri.0)] {
            let key = edgeKey(x, y)
            let (t0, t1) = incidence[key]!
            let owners = (alive[t0] ? 1 : 0) + (t1 >= 0 && alive[t1] ? 1 : 0)
            guard owners == 1, emitted.insert(key).inserted else { continue }
            neighborList[x].append(y)
            neighborList[y].append(x)
        }
    }
    let boundaryVertices = neighborList.indices.filter { !neighborList[$0].isEmpty }
    guard boundaryVertices.count >= 3,
          boundaryVertices.allSatisfy({ neighborList[$0].count == 2 })
    else { return convexHull(of: points) }
    for v in boundaryVertices { neighborList[v].sort() }

    let start = boundaryVertices.min { lexicographicallyBefore(points[$0], points[$1], $0, $1) }!
    var loop = [start]
    var previous = start
    var current = neighborList[start][0]
    while current != start, loop.count <= boundaryVertices.count {
        loop.append(current)
        let next = neighborList[current][0] == previous
            ? neighborList[current][1] : neighborList[current][0]
        previous = current
        current = next
    }

    var result = loop.map { points[$0] }
    if signedArea(result) < 0 {
        result = [result[0]] + result.dropFirst().reversed()
    }
    return result
}

/// The alpha shape of a point set: keep every Delaunay triangle whose
/// circumcircle a probe disk of radius `alpha` can't enter (circumradius at
/// most `alpha`), and the scatter's true footprint emerges. Unlike the
/// hulls, the result can split into several islands and can carry holes, so
/// it comes back as one `Shape` per island (outer boundary plus any hole
/// contours, even-odd). Small `alpha` dissolves the scatter into dust;
/// large `alpha` approaches the convex hull; `concaveHull(of:concavity:)`
/// is the sibling that always yields a single simple polygon.
///
/// Deterministic given the points. Fewer than three points, or an `alpha`
/// too small for any triangle, return an empty array.
public func alphaShape(of points: [Vector2], alpha: Double) -> [Shape] {
    guard alpha > 0 else { return [] }
    let tris = triangleList(of: Delaunay(points))
    guard !tris.isEmpty else { return [] }

    // The alpha complex, each triangle wound counterclockwise so the
    // boundary edges below walk consistently (interior on the left).
    var kept: [(Int, Int, Int)] = []
    for tri in tris {
        let pa = points[tri.0], pb = points[tri.1], pc = points[tri.2]
        let radius = Triangle(pa, pb, pc).circumcircle.radius
        guard radius > 0, radius <= alpha else { continue }
        kept.append((pb - pa).cross(pc - pa) < 0 ? (tri.0, tri.2, tri.1) : tri)
    }
    guard !kept.isEmpty else { return [] }

    // Count each undirected edge across the kept triangles (1 owner means
    // boundary) and union triangles that share an edge into islands.
    var edgeCount: [UInt64: Int] = [:]
    var firstOwner: [UInt64: Int] = [:]
    var parent = Array(kept.indices)
    func find(_ i: Int) -> Int {
        var root = i
        while parent[root] != root { root = parent[root] }
        var cur = i
        while parent[cur] != root { let next = parent[cur]; parent[cur] = root; cur = next }
        return root
    }
    for (k, tri) in kept.enumerated() {
        for (x, y) in [(tri.0, tri.1), (tri.1, tri.2), (tri.2, tri.0)] {
            let key = edgeKey(x, y)
            edgeCount[key, default: 0] += 1
            if let other = firstOwner[key] { parent[find(other)] = find(k) }
            else { firstOwner[key] = k }
        }
    }

    // Directed boundary edges in kept-triangle order; `outgoing` lists each
    // vertex's departures in that same order, so walks are deterministic.
    var boundaryEdges: [(from: Int, to: Int, owner: Int)] = []
    var outgoing: [Int: [Int]] = [:]
    for (k, tri) in kept.enumerated() {
        for (x, y) in [(tri.0, tri.1), (tri.1, tri.2), (tri.2, tri.0)] {
            guard edgeCount[edgeKey(x, y)] == 1 else { continue }
            outgoing[x, default: []].append(boundaryEdges.count)
            boundaryEdges.append((x, y, k))
        }
    }

    // Link the boundary edges into closed loops. At a pinch vertex (two
    // islands or a hole touching at one point) take the clockwise-most
    // departure relative to the reversed arrival, which keeps every loop on
    // its own face.
    var used = [Bool](repeating: false, count: boundaryEdges.count)
    var loops: [(points: [Vector2], owner: Int)] = []
    for e in boundaryEdges.indices where !used[e] {
        var vertices: [Int] = []
        var current = e
        var broken = false
        while true {
            used[current] = true
            let (u, v, _) = boundaryEdges[current]
            vertices.append(u)
            let candidates = (outgoing[v] ?? []).filter { !used[$0] || $0 == e }
            var next = -1
            if candidates.count == 1 {
                next = candidates[0]
            } else if candidates.count > 1 {
                let back = points[u] - points[v]
                let base = atan2(back.y, back.x)
                var bestAngle = -Double.infinity
                for c in candidates {
                    let d = points[boundaryEdges[c].to] - points[v]
                    var angle = atan2(d.y, d.x) - base
                    while angle <= 0 { angle += 2 * .pi }
                    if angle > bestAngle || (angle == bestAngle && c < next) {
                        bestAngle = angle
                        next = c
                    }
                }
            }
            if next == -1 { broken = true; break }
            if next == e { break }
            current = next
        }
        guard !broken, vertices.count >= 3 else { continue }
        // Canonical start: rotate the loop to its lexicographically smallest
        // vertex so the output never depends on which edge seeded the walk.
        var smallest = 0
        for i in vertices.indices where lexicographicallyBefore(
            points[vertices[i]], points[vertices[smallest]], vertices[i], vertices[smallest]) {
            smallest = i
        }
        let rotated = Array(vertices[smallest...] + vertices[..<smallest])
        loops.append((rotated.map { points[$0] }, boundaryEdges[e].owner))
    }

    // One shape per island, its outer contour (the largest loop) first and
    // its holes after. Islands sort by their outer loop's points, not by
    // triangle order: the triangulation's triangle *set* is stable but its
    // order isn't across processes, and the output must be.
    var islandOrder: [Int] = []
    var loopsOfIsland: [Int: [Int]] = [:]
    for (i, loop) in loops.enumerated() {
        let root = find(loop.owner)
        if loopsOfIsland[root] == nil {
            islandOrder.append(root)
            loopsOfIsland[root] = []
        }
        loopsOfIsland[root]!.append(i)
    }
    var shapes = islandOrder.map { root in
        let ordered = loopsOfIsland[root]!.sorted {
            let a = abs(signedArea(loops[$0].points))
            let b = abs(signedArea(loops[$1].points))
            return a != b ? a > b : pointsBefore(loops[$0].points, loops[$1].points)
        }
        return Shape(contours: ordered.map { Contour(loops[$0].points, closed: true) })
    }
    shapes.sort { pointsBefore($0.contours[0].points, $1.contours[0].points) }
    return shapes
}

// MARK: - Shared machinery (file-private)

/// Repair the mesh boundary where a hairline convex-hull sliver went
/// missing: find hull edges absent from the triangulation, walk the notch
/// path that stands in for each, and cap it with a fan of sliver triangles
/// so the outer boundary is exactly the convex hull.
private func capHullNotches(_ tris: inout [(Int, Int, Int)],
                            _ incidence: inout [UInt64: (Int, Int)],
                            _ points: [Vector2],
                            _ minLength: inout Double,
                            _ maxLength: inout Double) {
    // The mesh's index for each coordinate (a coincident duplicate resolves
    // to the one index the mesh actually used).
    var meshIndex: [PointKey: Int] = [:]
    for tri in tris {
        for v in [tri.0, tri.1, tri.2] where meshIndex[PointKey(points[v])] == nil {
            meshIndex[PointKey(points[v])] = v
        }
    }
    let hull = convexHull(of: points).compactMap { meshIndex[PointKey($0)] }
    guard hull.count >= 3 else { return }
    var isHullVertex = [Bool](repeating: false, count: points.count)
    for v in hull { isHullVertex[v] = true }
    let missing = (0 ..< hull.count).filter {
        incidence[edgeKey(hull[$0], hull[($0 + 1) % hull.count])] == nil
    }
    guard !missing.isEmpty else { return }

    // Boundary adjacency of the uncapped mesh, in triangle order.
    var neighborList = [[Int]](repeating: [], count: points.count)
    var emitted = Set<UInt64>()
    for tri in tris {
        for (x, y) in [(tri.0, tri.1), (tri.1, tri.2), (tri.2, tri.0)] {
            let key = edgeKey(x, y)
            guard incidence[key]!.1 == -1, emitted.insert(key).inserted else { continue }
            neighborList[x].append(y)
            neighborList[y].append(x)
        }
    }
    for v in neighborList.indices { neighborList[v].sort() }

    for i in missing {
        let a = hull[i]
        let b = hull[(i + 1) % hull.count]
        // The notch path runs from `a` to `b` along the mesh boundary
        // through non-hull vertices only; try both directions out of `a`.
        var path: [Int] = []
        for first in neighborList[a] where !isHullVertex[first] || first == b {
            var walk = [a, first]
            var previous = a
            var current = first
            while current != b, !isHullVertex[current], walk.count <= 32 {
                let nexts = neighborList[current].filter { $0 != previous }
                guard nexts.count == 1 else { break }
                previous = current
                current = nexts[0]
                walk.append(current)
            }
            if current == b { path = walk; break }
        }
        guard path.count >= 3, path.last == b else { continue }

        // Fan the notch polygon from `a`; every new edge joins the length
        // range the concavity knob interpolates over.
        for k in 1 ..< path.count - 1 {
            let t = tris.count
            tris.append((a, path[k], path[k + 1]))
            for (x, y) in [(a, path[k]), (path[k], path[k + 1]), (path[k + 1], a)] {
                let key = edgeKey(x, y)
                if let existing = incidence[key] {
                    incidence[key] = (existing.0, t)
                } else {
                    incidence[key] = (t, -1)
                    let length = (points[x] - points[y]).length
                    minLength = min(minLength, length)
                    maxLength = max(maxLength, length)
                }
            }
        }
    }
}

/// A coordinate as a hashable dictionary key, exact to the bit.
private struct PointKey: Hashable {
    let x: UInt64, y: UInt64
    init(_ p: Vector2) {
        x = p.x.bitPattern
        y = p.y.bitPattern
    }
}

/// The triangles of a `Delaunay` as index triples, walked from the flat
/// `indices` array once.
private func triangleList(of delaunay: Delaunay) -> [(Int, Int, Int)] {
    var result: [(Int, Int, Int)] = []
    result.reserveCapacity(delaunay.indices.count / 3)
    var k = 0
    while k + 2 < delaunay.indices.count {
        result.append((delaunay.indices[k], delaunay.indices[k + 1], delaunay.indices[k + 2]))
        k += 3
    }
    return result
}

/// An undirected edge packed into one key, ordered so both windings match.
private func edgeKey(_ x: Int, _ y: Int) -> UInt64 {
    let lo = UInt64(min(x, y)), hi = UInt64(max(x, y))
    return lo << 32 | hi
}

/// Twice-signed-area shoelace, halved: positive one winding, negative the
/// other, zero when degenerate.
private func signedArea(_ points: [Vector2]) -> Double {
    guard points.count >= 3 else { return 0 }
    var sum = 0.0
    for i in points.indices {
        let p = points[i]
        let q = points[(i + 1) % points.count]
        sum += p.x * q.y - q.x * p.y
    }
    return sum * 0.5
}

/// Strict lexicographic point order with an index tie-break, the
/// deterministic "smallest corner" rule the canonical starts use.
private func lexicographicallyBefore(_ a: Vector2, _ b: Vector2, _ ia: Int, _ ib: Int) -> Bool {
    if a.x != b.x { return a.x < b.x }
    if a.y != b.y { return a.y < b.y }
    return ia < ib
}

/// Pointwise lexicographic order of two point runs, the tie-break that keeps
/// island order independent of triangle order.
private func pointsBefore(_ a: [Vector2], _ b: [Vector2]) -> Bool {
    for i in 0 ..< min(a.count, b.count) {
        if a[i].x != b[i].x { return a[i].x < b[i].x }
        if a[i].y != b[i].y { return a[i].y < b[i].y }
    }
    return a.count < b.count
}

/// A max-heap of boundary edges, longest first with a fixed key tie-break,
/// so erosion order is deterministic.
private struct EdgeHeap {
    private var items: [(length: Double, key: UInt64)] = []

    mutating func push(_ item: (length: Double, key: UInt64)) {
        items.append(item)
        var i = items.count - 1
        while i > 0 {
            let parent = (i - 1) / 2
            guard precedes(items[i], items[parent]) else { break }
            items.swapAt(i, parent)
            i = parent
        }
    }

    mutating func pop() -> (length: Double, key: UInt64)? {
        guard let first = items.first else { return nil }
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var i = 0
            while true {
                let l = 2 * i + 1, r = 2 * i + 2
                var m = i
                if l < items.count, precedes(items[l], items[m]) { m = l }
                if r < items.count, precedes(items[r], items[m]) { m = r }
                if m == i { break }
                items.swapAt(i, m)
                i = m
            }
        }
        return first
    }

    private func precedes(_ a: (length: Double, key: UInt64),
                          _ b: (length: Double, key: UInt64)) -> Bool {
        a.length != b.length ? a.length > b.length : a.key < b.key
    }
}
