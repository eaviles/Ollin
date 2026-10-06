import Foundation

// The regions a drawing encloses. A set of outlines, open or closed, is read
// as the lines on a page: every segment is cut where it meets another or
// itself, the pieces form a map (a planar graph), and each face of that map
// comes back as its own `Shape`, the way a coloring book has one region for
// every patch its lines wall off. The map is the planar arrangement, and the
// faces are traced by walking it as a doubly connected edge list: at every
// vertex the walk takes the next edge round, so each walk goes once round one
// face with that face on its left.

/// Every region a set of outlines encloses, each as its own `Shape`.
///
/// The outlines are read as drawn. Where two of them cross, or one crosses
/// itself, both are cut there, and the pieces wall the page into regions: two
/// overlapping circles give three (the lens and the two crescents), a grid of
/// lines gives its cells, and a page of scribbles gives every patch a pen
/// could color without crossing a line. Each region comes back as a `Shape`
/// whose outline lies on the input lines, so the regions together cover
/// exactly what the lines wall off (a patch of bare page ringed by three
/// circles is a region as much as the circles' lenses are), no two overlap,
/// and every one can take a fill of its own.
///
/// ```swift
/// let discs = (0 ..< 5).map { i in
///     Circle(center: Vector2(540, 540) + Vector2(angle: Double(i) / 5 * .tau, length: 180),
///            radius: 260).contour()
/// }
/// for (i, region) in regions(enclosedBy: discs).enumerated() {
///     fill(palette.color(at: Double(i) / 12))
///     drawShape(region)
/// }
/// ```
///
/// A region inside another is a region of its own and also a hole in the one
/// around it, so a small circle drawn inside a large one gives the disc and
/// the ring, and the ring's `Shape` carries the disc as a hole. An open line
/// counts where it crosses something and is dropped where it leads nowhere:
/// a stroke whose end hangs loose inside a region walls nothing off, and a
/// line that crosses a circle cuts it in two. Lines that run along each
/// other share their stretch as one edge.
///
/// The regions come back in reading order (by the top of each one's bounds,
/// then its left edge), and the same outlines give the same regions in the
/// same order. A drawing that moves changes which regions exist from frame to
/// frame, so key a region's color by something of its own, such as its
/// `centroid`, rather than by its place in the list.
///
/// The work is a sweep over the segments for the crossings, then one walk
/// round every face, so a drawing of a few thousand segments is comfortable
/// each frame and one of a few hundred thousand belongs in `setup()`. Points
/// closer together than a billionth of the drawing's extent are read as one.
public func regions(enclosedBy contours: [Contour]) -> [Shape] {
    PlanarArrangement.regions(of: contours)
}

/// Every region a set of shapes encloses: `regions(enclosedBy:)` over every
/// contour of every shape, so two overlapping shapes with holes give the
/// regions their outlines wall off between them.
public func regions(enclosedBy shapes: [Shape]) -> [Shape] {
    regions(enclosedBy: shapes.flatMap(\.contours))
}

// MARK: - The arrangement

enum PlanarArrangement {
    /// One straight piece of an input outline.
    struct Line {
        let a: Vector2
        let b: Vector2
    }

    /// The faces of the map the contours draw, as shapes in reading order.
    static func regions(of contours: [Contour]) -> [Shape] {
        // Every segment, with the return leg of a closed outline; zero-length
        // and non-finite ones carry nothing.
        var lines: [Line] = []
        var low = Vector2(.infinity, .infinity), high = Vector2(-.infinity, -.infinity)
        for contour in contours {
            let points = contour.points
            guard points.count >= 2 else { continue }
            let count = contour.isClosed ? points.count : points.count - 1
            for i in 0 ..< count {
                let a = points[i], b = points[(i + 1) % points.count]
                guard a.x.isFinite, a.y.isFinite, b.x.isFinite, b.y.isFinite, a != b else { continue }
                lines.append(Line(a: a, b: b))
                low = Vector2(Swift.min(low.x, a.x, b.x), Swift.min(low.y, a.y, b.y))
                high = Vector2(Swift.max(high.x, a.x, b.x), Swift.max(high.y, a.y, b.y))
            }
        }
        guard lines.count >= 3 else { return [] }
        let scale = Swift.max(high.x - low.x, high.y - low.y)
        guard scale > 0 else { return [] }
        let epsilon = scale * 1e-9

        // Where each line is cut: the parameter along it of every crossing
        // that lands strictly inside it. The sweep hands over every pair
        // whose extents overlap, which is the broad phase the crossings use.
        var cuts = [[Double]](repeating: [], count: lines.count)
        let segments = lines.map {
            Contour.Segment(a: $0.a, b: $0.b, start: 0, length: ($0.b - $0.a).length,
                            direction: ($0.b - $0.a).normalized)
        }
        Contour.sweep(segments, nil) { i, j in
            var onI: [Double] = [], onJ: [Double] = []
            cut(lines[i], lines[j], epsilon: epsilon, into: &onI, &onJ)
            cuts[i] += onI
            cuts[j] += onJ
        }

        // The pieces, and the vertices they meet at. Every endpoint lands on a
        // vertex, with ends closer than `epsilon` read as one, so the two
        // reports of one crossing (one from each line) become the same point.
        var snap = VertexSnap(origin: low, epsilon: epsilon)
        var edges: [(a: Int, b: Int)] = []
        var seen = Set<Int64>()
        func addEdge(_ p: Vector2, _ q: Vector2) {
            let i = snap.vertex(for: p), j = snap.vertex(for: q)
            guard i != j else { return }
            let (lo, hi) = i < j ? (i, j) : (j, i)
            guard seen.insert(Int64(lo) << 32 | Int64(hi)).inserted else { return }
            edges.append((lo, hi))
        }
        for (i, line) in lines.enumerated() {
            var previous = line.a
            var last = 0.0
            for t in cuts[i].sorted() where t - last > 1e-12 {
                let point = line.a + (line.b - line.a) * t
                addEdge(previous, point)
                previous = point
                last = t
            }
            addEdge(previous, line.b)
        }
        let vertices = snap.points

        // An edge that is the only way between two parts of the map bounds
        // no region: a stroke hanging loose, a line joining two loops. Every
        // edge left after dropping those lies on a cycle.
        let isBridge = bridges(vertexCount: vertices.count, edges: edges)
        let kept = edges.indices.filter { !isBridge[$0] }
        guard !kept.isEmpty else { return [] }

        // Round every vertex, its edges in angular order, and where each edge
        // sits in that order at each of its ends.
        var around = [[(edge: Int, to: Int, angle: Double)]](repeating: [], count: vertices.count)
        for e in kept {
            let (a, b) = edges[e]
            let d = vertices[b] - vertices[a]
            around[a].append((e, b, atan2(d.y, d.x)))
            around[b].append((e, a, atan2(-d.y, -d.x)))
        }
        var slotAtA = [Int](repeating: 0, count: edges.count)
        var slotAtB = [Int](repeating: 0, count: edges.count)
        for v in around.indices {
            around[v].sort { $0.angle < $1.angle || ($0.angle == $1.angle && $0.edge < $1.edge) }
            for (slot, entry) in around[v].enumerated() {
                if edges[entry.edge].a == v { slotAtA[entry.edge] = slot } else { slotAtB[entry.edge] = slot }
            }
        }
        let component = components(vertexCount: vertices.count, edges: edges, kept: kept)

        // Walk every face once. A half edge is an edge and a direction; at
        // the far vertex the walk takes the edge just clockwise of the one it
        // arrived by, which keeps the face on its left. A bounded face then
        // walks one way round (positive area) and the outside of each
        // connected part of the map the other.
        struct Face {
            let points: [Vector2]
            let area: Double
            let component: Int
        }
        var visited = [Bool](repeating: false, count: edges.count * 2)
        var bounded: [Face] = []
        var outsides: [Face] = []
        for e in kept {
            for direction in 0 ..< 2 {
                let start = e * 2 + direction
                guard !visited[start] else { continue }
                var cycle: [Vector2] = []
                var current = start
                var steps = 0
                repeat {
                    visited[current] = true
                    let edge = edges[current / 2]
                    let (from, to) = current % 2 == 0 ? (edge.a, edge.b) : (edge.b, edge.a)
                    cycle.append(vertices[from])
                    let list = around[to]
                    let slot = edges[current / 2].a == to ? slotAtA[current / 2] : slotAtB[current / 2]
                    let next = list[(slot - 1 + list.count) % list.count]
                    current = next.edge * 2 + (edges[next.edge].a == to ? 0 : 1)
                    steps += 1
                } while current != start && steps <= edges.count * 2
                let area = Shape.signedArea(cycle)
                let face = Face(points: cycle, area: area, component: component[edges[e].a])
                if area > epsilon * epsilon {
                    bounded.append(face)
                } else if area < -epsilon * epsilon {
                    outsides.append(face)
                }
            }
        }

        // The outside of one part of the map that lies inside a face of
        // another is a hole in that face: the smallest face of another part
        // that contains it. A part's own faces never hold its own outside.
        var holes = [[Contour]](repeating: [], count: bounded.count)
        for outside in outsides {
            guard let probe = outside.points.first else { continue }
            var owner = -1
            var smallest = Double.infinity
            for (i, face) in bounded.enumerated()
            where face.component != outside.component && face.area < smallest
                && Shape.contains(face.points, probe) {
                owner = i
                smallest = face.area
            }
            if owner >= 0 { holes[owner].append(Contour(outside.points, closed: true)) }
        }

        var shapes: [(top: Double, left: Double, area: Double, shape: Shape)] = []
        for (i, face) in bounded.enumerated() {
            let contours = [Contour(face.points, closed: true)] + holes[i]
            var top = Double.infinity, left = Double.infinity
            for p in face.points {
                top = Swift.min(top, p.y)
                left = Swift.min(left, p.x)
            }
            shapes.append((top, left, face.area, Shape(contours: contours, winding: .evenOdd)))
        }
        shapes.sort {
            if $0.top != $1.top { return $0.top < $1.top }
            if $0.left != $1.left { return $0.left < $1.left }
            return $0.area > $1.area
        }
        return shapes.map(\.shape)
    }

    /// Where two lines meet, as cuts along each. A crossing within `epsilon`
    /// of a line's end is not a cut (the end itself is the vertex, and the
    /// snap joins the two). Two lines along one another cut each other where
    /// the other's ends fall inside them, so an overlap becomes one shared
    /// edge between two pieces.
    static func cut(_ p: Line, _ q: Line, epsilon: Double,
                    into ps: inout [Double], _ qs: inout [Double]) {
        let r = p.b - p.a, v = q.b - q.a
        let rLength = r.length, vLength = v.length
        let gap = q.a - p.a
        let denominator = r.cross(v)
        if abs(denominator) > 1e-12 * rLength * vLength {
            let s = gap.cross(v) / denominator
            let u = gap.cross(r) / denominator
            let sTolerance = epsilon / rLength, uTolerance = epsilon / vLength
            guard s >= -sTolerance, s <= 1 + sTolerance,
                  u >= -uTolerance, u <= 1 + uTolerance else { return }
            if s > sTolerance && s < 1 - sTolerance { ps.append(s) }
            if u > uTolerance && u < 1 - uTolerance { qs.append(u) }
            return
        }
        // Parallel: along one line, or on two different ones.
        guard abs(gap.cross(r)) <= epsilon * rLength else { return }
        for point in [q.a, q.b] {
            let along = (point - p.a).dot(r) / rLength
            if along > epsilon && along < rLength - epsilon { ps.append(along / rLength) }
        }
        for point in [p.a, p.b] {
            let along = (point - q.a).dot(v) / vLength
            if along > epsilon && along < vLength - epsilon { qs.append(along / vLength) }
        }
    }

    /// Points read as one when they fall within `epsilon` of each other: a
    /// grid of cells `epsilon` across, so a point's twin is in its own cell or
    /// one of the eight around it.
    struct VertexSnap {
        private(set) var points: [Vector2] = []
        private var cells: [Int64: [Int]] = [:]
        private let origin: Vector2
        private let epsilon: Double

        init(origin: Vector2, epsilon: Double) {
            self.origin = origin
            self.epsilon = epsilon
        }

        private func key(_ cx: Int64, _ cy: Int64) -> Int64 {
            cx &* Int64(bitPattern: 0x9E37_79B9_7F4A_7C15 as UInt64) ^ cy
        }

        mutating func vertex(for p: Vector2) -> Int {
            let fx = (p.x - origin.x) / epsilon, fy = (p.y - origin.y) / epsilon
            let cx = Int64(fx.rounded(.down)), cy = Int64(fy.rounded(.down))
            var best = -1
            var bestDistance = epsilon * epsilon
            for dx in -1 ... 1 {
                for dy in -1 ... 1 {
                    guard let bucket = cells[key(cx + Int64(dx), cy + Int64(dy))] else { continue }
                    for i in bucket {
                        let d = points[i].distanceSquared(to: p)
                        if d <= bestDistance { bestDistance = d; best = i }
                    }
                }
            }
            if best >= 0 { return best }
            points.append(p)
            cells[key(cx, cy), default: []].append(points.count - 1)
            return points.count - 1
        }
    }

    /// Which edges are bridges, the ones whose removal cuts the map in two:
    /// a depth-first search that keeps its pending work on a list, since the
    /// map's depth is the drawing's.
    static func bridges(vertexCount: Int, edges: [(a: Int, b: Int)]) -> [Bool] {
        var around = [[(edge: Int, to: Int)]](repeating: [], count: vertexCount)
        for (e, edge) in edges.enumerated() {
            around[edge.a].append((e, edge.b))
            around[edge.b].append((e, edge.a))
        }
        var found = [Int](repeating: -1, count: vertexCount)
        var reach = [Int](repeating: 0, count: vertexCount)
        var isBridge = [Bool](repeating: false, count: edges.count)
        var clock = 0
        for root in 0 ..< vertexCount where found[root] < 0 {
            var pending: [(vertex: Int, by: Int, next: Int)] = [(root, -1, 0)]
            found[root] = clock
            reach[root] = clock
            clock += 1
            while let top = pending.last {
                let (v, by, i) = top
                if i < around[v].count {
                    pending[pending.count - 1].next += 1
                    let (e, w) = around[v][i]
                    if e == by { continue }
                    if found[w] < 0 {
                        found[w] = clock
                        reach[w] = clock
                        clock += 1
                        pending.append((w, e, 0))
                    } else {
                        reach[v] = Swift.min(reach[v], found[w])
                    }
                } else {
                    pending.removeLast()
                    if let parent = pending.last {
                        reach[parent.vertex] = Swift.min(reach[parent.vertex], reach[v])
                        if reach[v] > found[parent.vertex] { isBridge[by] = true }
                    }
                }
            }
        }
        return isBridge
    }

    /// The connected part each vertex belongs to, over the kept edges.
    static func components(vertexCount: Int, edges: [(a: Int, b: Int)], kept: [Int]) -> [Int] {
        var parent = Array(0 ..< vertexCount)
        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x {
                parent[x] = parent[parent[x]]
                x = parent[x]
            }
            return x
        }
        for e in kept {
            let a = find(edges[e].a), b = find(edges[e].b)
            if a != b { parent[a] = b }
        }
        return (0 ..< vertexCount).map { find($0) }
    }
}
