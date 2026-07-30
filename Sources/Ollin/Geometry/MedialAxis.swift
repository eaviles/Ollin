import Foundation

/// The medial axis of a shape, its skeleton: the curve traced by the centers
/// of every disk that fits inside the region while touching the boundary in
/// two or more places. A blob collapses to its centerline veins, a
/// letterform to the stroke of the pen that could have written it. Every
/// skeleton point carries the radius of its inscribed disk, so the skeleton
/// knows how fat the shape is everywhere along it: stroke the branches for
/// pure line work, or draw the disks for a packed, cellular fill.
///
/// ```swift
/// let skeleton = medialAxis(of: blob, spacing: 3, prune: 6)
/// noFill(); stroke(.black)
/// for branch in skeleton.branches {
///     drawPolyline(branch.points, closed: branch.isClosed)
/// }
/// ```
///
/// Approximated the standard way: sample the boundary evenly, build the
/// Voronoi diagram of the samples, and keep the Voronoi edges that run
/// between non-neighboring samples without leaving the region. The result
/// converges to the true axis as `spacing` shrinks. Deterministic given the
/// shape, and setup-time-shaped: extract once and hold the branches.

/// A shape's skeleton: polyline `branches` whose every point carries the
/// radius of its inscribed disk. Returned by `medialAxis(of:spacing:prune:)`.
public struct MedialAxis: Equatable, Sendable {
    /// One skeleton branch: an open centerline run between branch points (or
    /// a closed ring, for a shape with a hole), with the inscribed-disk
    /// `radii` running 1:1 with `points`.
    public struct Branch: Equatable, Sendable {
        public let points: [Vector2]
        /// The clearance at each point: the radius of the largest disk that
        /// sits inside the shape centered there.
        public let radii: [Double]
        /// Whether the branch loops back on itself (a hole's ring does).
        public let isClosed: Bool

        public init(points: [Vector2], radii: [Double], isClosed: Bool) {
            self.points = points
            self.radii = radii
            self.isClosed = isClosed
        }

        /// The branch as a plain `Contour`, ready for `drawPolyline`,
        /// smoothing, or SVG export.
        public var contour: Contour { Contour(points, closed: isClosed) }
    }

    public let branches: [Branch]

    public init(branches: [Branch]) {
        self.branches = branches
    }

    /// Every branch as a plain `Contour`, radii dropped.
    public var contours: [Contour] { branches.map(\.contour) }
}

/// The medial axis of `shape`, approximated from a boundary sampling
/// `spacing` points apart (in the shape's own units): finer spacing, more
/// faithful skeleton, more work. `prune` trims the whiskers: terminal twigs
/// shorter than it (again in shape units) are removed, which cleans the
/// side branches that boundary corners and sampling noise grow; a couple of
/// spacings is a good starting value. Holes are honored (their skeleton
/// rings survive), and a multi-contour shape skeletonizes region by region.
/// Deterministic given the shape.
public func medialAxis(of shape: Shape, spacing: Double = 4, prune: Double = 0) -> MedialAxis {
    guard spacing > 0 else { return MedialAxis(branches: []) }

    // 1. Even samples along every boundary ring. Ring neighbors (consecutive
    //    samples, wrapping) are what "non-neighboring" tests against below.
    var samples: [Vector2] = []
    var ringOf: [Int] = []
    var indexInRing: [Int] = []
    var ringSize: [Int] = []
    var domainContours: [Contour] = []
    for contour in shape.contours {
        guard contour.points.count >= 3 else { continue }
        let ring = Contour(contour.points, closed: true).resampled(spacing: spacing)
        guard ring.points.count >= 3 else { continue }
        for (i, p) in ring.points.enumerated() {
            samples.append(p)
            ringOf.append(ringSize.count)
            indexInRing.append(i)
        }
        ringSize.append(ring.points.count)
        domainContours.append(ring)
    }
    guard samples.count >= 4 else { return MedialAxis(branches: []) }
    let domain = Shape(contours: domainContours, winding: shape.winding)

    // 2. Voronoi vertices of the samples: each triangle's circumcenter, with
    //    the circumradius as its clearance (its distance to the nearest
    //    samples). Only centers inside the sampled region can carry skeleton.
    let tris = triangleList(of: Delaunay(samples))
    guard !tris.isEmpty else { return MedialAxis(branches: []) }
    var centers = [Vector2](repeating: .zero, count: tris.count)
    var radii = [Double](repeating: 0, count: tris.count)
    var inside = [Bool](repeating: false, count: tris.count)
    for (t, tri) in tris.enumerated() {
        let circle = Triangle(samples[tri.0], samples[tri.1], samples[tri.2]).circumcircle
        centers[t] = circle.center
        radii[t] = circle.radius
        inside[t] = circle.radius > 0 && domain.contains(circle.center)
    }

    func ringNeighbors(_ p: Int, _ q: Int) -> Bool {
        guard ringOf[p] == ringOf[q] else { return false }
        let count = ringSize[ringOf[p]]
        let d = abs(indexInRing[p] - indexInRing[q])
        return d == 1 || d == count - 1
    }

    // 3. The skeleton's segments: the Voronoi edge between two adjacent
    //    triangles survives when its dual Delaunay edge jumps across the
    //    region (its samples aren't ring neighbors) and both circumcenters
    //    stay inside. Scanned in triangle order; the map is only indexed.
    var firstTri: [UInt64: Int] = [:]
    var edges: [(Int, Int)] = []
    for (t, tri) in tris.enumerated() {
        for (x, y) in [(tri.0, tri.1), (tri.1, tri.2), (tri.2, tri.0)] {
            let key = edgeKey(x, y)
            if let s = firstTri[key] {
                if inside[s], inside[t], !ringNeighbors(x, y) {
                    edges.append((s, t))
                }
            } else {
                firstTri[key] = t
            }
        }
    }
    guard !edges.isEmpty else { return MedialAxis(branches: []) }

    // 4. The skeleton graph over those segments.
    var incident = [[Int]](repeating: [], count: tris.count)
    for (e, pair) in edges.enumerated() {
        incident[pair.0].append(e)
        incident[pair.1].append(e)
    }
    var edgeAlive = [Bool](repeating: true, count: edges.count)
    var degree = [Int](repeating: 0, count: tris.count)
    for pair in edges {
        degree[pair.0] += 1
        degree[pair.1] += 1
    }
    func aliveSteps(from v: Int) -> [(edge: Int, vertex: Int)] {
        incident[v].compactMap { e in
            guard edgeAlive[e] else { return nil }
            let (a, b) = edges[e]
            return (e, a == v ? b : a)
        }
    }

    // 5. Prune: walk each terminal twig from its tip to the first branch
    //    point; shorter than `prune`, it goes. Repeated until stable, so a
    //    branch point stripped of all its twigs can become a tip itself. A
    //    twig that is a whole component (no branch point) always stays.
    if prune > 0 {
        var removed = true
        while removed {
            removed = false
            // Collect the round's doomed twigs against the round-start graph,
            // then remove them together: removing one twig mid-round would
            // turn its branch point into a pass-through and let a sibling's
            // walk run on past it.
            var doomed: [Int] = []
            for tip in 0 ..< tris.count where degree[tip] == 1 {
                var chain: [Int] = []
                var length = 0.0
                var current = tip
                var arrivedBy = -1
                while current == tip || degree[current] == 2 {
                    let steps = aliveSteps(from: current).filter { $0.edge != arrivedBy }
                    guard steps.count == 1 else { break }
                    let step = steps[0]
                    let (a, b) = edges[step.edge]
                    chain.append(step.edge)
                    length += (centers[a] - centers[b]).length
                    current = step.vertex
                    arrivedBy = step.edge
                    if length >= prune { break }
                }
                guard length < prune, degree[current] >= 3, !chain.isEmpty else { continue }
                doomed.append(contentsOf: chain)
            }
            for e in doomed where edgeAlive[e] {
                edgeAlive[e] = false
                degree[edges[e].0] -= 1
                degree[edges[e].1] -= 1
                removed = true
            }
        }
    }

    // 6. Decompose what's left into branches: open chains run between
    //    vertices whose degree isn't 2 (tips and branch points), walked in
    //    vertex order; whatever remains is pure rings, walked closed. The
    //    incident lists were built in edge order, so both walks are
    //    deterministic.
    var consumed = [Bool](repeating: false, count: edges.count)
    var branches: [MedialAxis.Branch] = []
    func emit(_ ids: [Int], closed: Bool) {
        var pts: [Vector2] = []
        var rads: [Double] = []
        for id in ids {
            let p = centers[id]
            if let last = pts.last, (p - last).length < 1e-9 { continue }
            pts.append(p)
            rads.append(radii[id])
        }
        if closed, pts.count >= 2, (pts[0] - pts[pts.count - 1]).length < 1e-9 {
            pts.removeLast()
            rads.removeLast()
        }
        guard pts.count >= (closed ? 3 : 2) else { return }
        // Canonical direction (and start, for rings): the triangulation's
        // triangle *set* is stable but its order isn't across processes, so
        // branch geometry decides, never walk order.
        if closed {
            var smallest = 0
            for i in pts.indices where pointBefore(pts[i], pts[smallest]) { smallest = i }
            pts = Array(pts[smallest...] + pts[..<smallest])
            rads = Array(rads[smallest...] + rads[..<smallest])
            if pts.count >= 3, pointBefore(pts[pts.count - 1], pts[1]) {
                pts = [pts[0]] + pts.dropFirst().reversed()
                rads = [rads[0]] + rads.dropFirst().reversed()
            }
        } else if pointBefore(pts[pts.count - 1], pts[0]) {
            pts.reverse()
            rads.reverse()
        }
        branches.append(MedialAxis.Branch(points: pts, radii: rads, isClosed: closed))
    }

    for v in 0 ..< tris.count where degree[v] > 0 && degree[v] != 2 {
        for start in aliveSteps(from: v) where !consumed[start.edge] {
            var ids = [v]
            var step = start
            while true {
                consumed[step.edge] = true
                ids.append(step.vertex)
                guard degree[step.vertex] == 2 else { break }
                let nexts = aliveSteps(from: step.vertex).filter { !consumed[$0.edge] }
                guard nexts.count == 1 else { break }
                step = nexts[0]
            }
            emit(ids, closed: false)
        }
    }
    for e in edges.indices where edgeAlive[e] && !consumed[e] {
        let startVertex = min(edges[e].0, edges[e].1)
        var ids = [startVertex]
        var current = startVertex
        while true {
            let nexts = aliveSteps(from: current).filter { !consumed[$0.edge] }
            guard let step = nexts.first else { break }
            consumed[step.edge] = true
            current = step.vertex
            if current == startVertex { break }
            ids.append(current)
        }
        emit(ids, closed: true)
    }
    branches.sort {
        let a = $0.points, b = $1.points
        for i in 0 ..< Swift.min(a.count, b.count) where a[i] != b[i] {
            return pointBefore(a[i], b[i])
        }
        return a.count < b.count
    }
    return MedialAxis(branches: branches)
}

// MARK: - Shared machinery (file-private)

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

/// Strict lexicographic point order, the deterministic rule the canonical
/// branch starts and directions use.
private func pointBefore(_ a: Vector2, _ b: Vector2) -> Bool {
    a.x != b.x ? a.x < b.x : a.y < b.y
}
