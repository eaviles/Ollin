import Foundation

/// A triangle of three points, the unit a `Delaunay` triangulation is made of.
///
/// Beyond the three corners it carries the geometry a tessellation usually wants
/// next: the `centroid`, the `circumcircle` (the circle through all three
/// corners — its center is a Voronoi vertex), and a fillable `shape`/`contour`
/// so a triangle drops straight into `drawShape`, the booleans, or hatching.
public struct Triangle: Equatable, Sendable {
    public let a: Vector2
    public let b: Vector2
    public let c: Vector2

    public init(_ a: Vector2, _ b: Vector2, _ c: Vector2) {
        self.a = a
        self.b = b
        self.c = c
    }

    /// The three corners, in order.
    public var points: [Vector2] { [a, b, c] }

    /// The average of the three corners.
    public var centroid: Vector2 { (a + b + c) / 3 }

    /// Unsigned area.
    public var area: Double { abs((b - a).cross(c - a)) * 0.5 }

    /// The circle through all three corners. Its center (the *circumcenter*) is a
    /// vertex of the dual Voronoi diagram. Degenerate (collinear) triangles
    /// report a zero-radius circle at the centroid.
    public var circumcircle: Circle {
        guard let (center, r2) = circumcircleOf(a, b, c) else {
            return Circle(center: centroid, radius: 0)
        }
        return Circle(center: center, radius: r2.squareRoot())
    }

    /// The center of the `circumcircle` — a Voronoi vertex.
    public var circumcenter: Vector2 { circumcircle.center }

    /// The triangle as a closed contour.
    public var contour: Contour { Contour([a, b, c], closed: true) }

    /// The triangle as a fillable shape.
    public var shape: Shape { Shape([a, b, c]) }
}

/// A Delaunay triangulation of a set of points: the triangulation that maximizes
/// the smallest angle, so the triangles are as well-shaped (un-slivery) as the
/// points allow. It's the foundation the dual `Voronoi` diagram is built on, and
/// a building block in its own right (irregular meshes, terrain, point-cloud
/// surfaces).
///
/// Built with the Bowyer–Watson incremental algorithm. The result is `points`
/// plus a flat `indices` array — three entries per triangle, each an index into
/// `points` — with `triangles` resolving them into `Triangle` values.
///
/// ```swift
/// let sites = (0..<200).map { _ in randomVector(in: bounds) }
/// let mesh = Delaunay(sites)
/// noFill(); stroke(.black)
/// for t in mesh.triangles { drawShape(t.shape) }
/// let cells = mesh.voronoi(bounds: bounds).cells   // the dual diagram
/// ```
///
/// Sites are taken as given (no clustering or dedup): scatter them with the
/// seedable `random`/`noise` helpers and the same seed always yields the same
/// triangulation. Exactly-coincident points are skipped during insertion, so
/// they don't corrupt the mesh; fully collinear inputs simply produce no
/// triangles.
public struct Delaunay: Sendable {
    /// The input points, in their original order.
    public let points: [Vector2]

    /// Triangle corners as a flat list of indices into `points`, three per
    /// triangle (`indices[0..<3]` is the first triangle, and so on). The order
    /// is canonical: each triple starts at its smallest index, winds so the
    /// triangle's signed area in canvas space is non-negative, and triangles
    /// are sorted by their triples, so the same input always yields the same
    /// list, byte for byte.
    public let indices: [Int]

    /// Triangulate `points`. Points are used as given, in order.
    public init(_ points: [Vector2]) {
        self.points = points
        self.indices = Delaunay.triangulate(points)
    }

    /// The triangles, resolved from `indices` into corner points.
    public var triangles: [Triangle] {
        var result: [Triangle] = []
        result.reserveCapacity(indices.count / 3)
        var i = 0
        while i + 2 < indices.count {
            result.append(Triangle(points[indices[i]], points[indices[i + 1]], points[indices[i + 2]]))
            i += 3
        }
        return result
    }

    /// Each triangle as a fillable `Shape`.
    public var triangleShapes: [Shape] { triangles.map(\.shape) }

    /// The indices of the points sharing a triangle edge with point `i` — its
    /// Delaunay neighbors, which are exactly the sites whose Voronoi cells border
    /// `i`'s.
    public func neighbors(of i: Int) -> [Int] {
        var set = Set<Int>()
        var k = 0
        while k + 2 < indices.count {
            let a = indices[k], b = indices[k + 1], c = indices[k + 2]
            if a == i || b == i || c == i {
                if a != i { set.insert(a) }
                if b != i { set.insert(b) }
                if c != i { set.insert(c) }
            }
            k += 3
        }
        return set.sorted()
    }

    /// The dual Voronoi diagram, clipped to `bounds`.
    public func voronoi(bounds: Rectangle) -> Voronoi {
        Voronoi(delaunay: self, bounds: bounds)
    }

    // MARK: - Bowyer–Watson

    private struct Tri {
        let a: Int, b: Int, c: Int
        let cx: Double, cy: Double, r2: Double

        /// Whether `p` lies inside (or on) the circumcircle. A degenerate
        /// triangle (`r2 < 0`) contains nothing, so it never disrupts insertion.
        func circumcircleContains(_ p: Vector2) -> Bool {
            let dx = p.x - cx, dy = p.y - cy
            return dx * dx + dy * dy <= r2 + 1e-9
        }
    }

    /// An undirected edge, ordered so the two windings hash equal.
    private struct Edge: Hashable {
        let lo: Int, hi: Int
        init(_ x: Int, _ y: Int) {
            if x < y { lo = x; hi = y } else { lo = y; hi = x }
        }
    }

    private static func makeTri(_ a: Int, _ b: Int, _ c: Int, _ pts: [Vector2]) -> Tri {
        if let (center, r2) = circumcircleOf(pts[a], pts[b], pts[c]) {
            return Tri(a: a, b: b, c: c, cx: center.x, cy: center.y, r2: r2)
        }
        // Collinear/degenerate: mark with r2 < 0 so it contains no point.
        return Tri(a: a, b: b, c: c, cx: 0, cy: 0, r2: -1)
    }

    private static func triangulate(_ input: [Vector2]) -> [Int] {
        guard input.count >= 3 else { return [] }

        // A super-triangle large enough to contain every input point.
        var minX = input[0].x, maxX = input[0].x
        var minY = input[0].y, maxY = input[0].y
        for p in input {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let span = max(max(maxX - minX, maxY - minY), 1)
        let midX = (minX + maxX) / 2, midY = (minY + maxY) / 2
        let n = input.count

        var pts = input
        pts.append(Vector2(midX - 20 * span, midY - span))      // index n
        pts.append(Vector2(midX,             midY + 20 * span)) // index n + 1
        pts.append(Vector2(midX + 20 * span, midY - span))      // index n + 2

        var tris = [makeTri(n, n + 1, n + 2, pts)]

        for i in 0..<n {
            let p = pts[i]

            // The triangles whose circumcircle swallows p must be retriangulated.
            var edgeCount: [Edge: Int] = [:]
            var survivors: [Tri] = []
            survivors.reserveCapacity(tris.count)
            for t in tris {
                if t.circumcircleContains(p) {
                    edgeCount[Edge(t.a, t.b), default: 0] += 1
                    edgeCount[Edge(t.b, t.c), default: 0] += 1
                    edgeCount[Edge(t.c, t.a), default: 0] += 1
                } else {
                    survivors.append(t)
                }
            }

            // Exactly-coincident point: it fell in no circumcircle, so leave the
            // mesh untouched rather than spawning zero-area triangles.
            if edgeCount.isEmpty { continue }

            tris = survivors
            // The hole's boundary is the edges owned by just one removed triangle;
            // fan p out to each of them.
            for (edge, count) in edgeCount where count == 1 {
                tris.append(makeTri(edge.lo, edge.hi, i, pts))
            }
        }

        // Drop everything still touching a super-triangle vertex, and put the
        // survivors in canonical order: the refan above iterates a Dictionary,
        // so the raw triangle order (and winding) varies per process while the
        // set is stable. Each triple is sorted ascending, wound so its signed
        // area in canvas space is non-negative, and the list is sorted by its
        // triples, so the same input yields the same output every run.
        var triples: [(a: Int, b: Int, c: Int)] = []
        triples.reserveCapacity(tris.count)
        for t in tris where t.a < n && t.b < n && t.c < n {
            var (a, b, c) = (t.a, t.b, t.c)
            if a > b { swap(&a, &b) }
            if b > c { swap(&b, &c) }
            if a > b { swap(&a, &b) }
            if (pts[b] - pts[a]).cross(pts[c] - pts[a]) < 0 { swap(&b, &c) }
            triples.append((a, b, c))
        }
        triples.sort { ($0.a, $0.b, $0.c) < ($1.a, $1.b, $1.c) }

        var out: [Int] = []
        out.reserveCapacity(triples.count * 3)
        for t in triples {
            out.append(t.a); out.append(t.b); out.append(t.c)
        }
        return out
    }
}

/// A Voronoi diagram: a partition of the plane into one convex cell per site,
/// where a cell is every point closer to its site than to any other. The dual of
/// a `Delaunay` triangulation, and the "stochastic crystallization" look — cells
/// that feel both random and inevitable.
///
/// Each cell is clipped to `bounds` (so boundary sites get finite cells), and
/// `cells` is 1:1 with `sites` in order. A cell is a convex `Shape`, ready for
/// `fill`/`stroke`, the booleans, hatching, or SVG export.
///
/// ```swift
/// let v = Voronoi(sites: points, bounds: bounds)
/// for (i, cell) in v.cells.enumerated() {
///     fill(palette[i]); drawShape(cell)
/// }
/// let evened = v.relaxed(iterations: 3)   // Lloyd's algorithm
/// ```
public struct Voronoi: Sendable {
    /// The sites, in input order.
    public let sites: [Vector2]
    /// The rectangle every cell is clipped to.
    public let bounds: Rectangle
    /// One convex cell per site, in the same order as `sites`.
    public let cells: [Shape]

    private let delaunay: Delaunay

    /// Build the diagram of `sites`, clipping every cell to `bounds`.
    public init(sites: [Vector2], bounds: Rectangle) {
        self.init(delaunay: Delaunay(sites), bounds: bounds)
    }

    init(delaunay: Delaunay, bounds: Rectangle) {
        self.delaunay = delaunay
        self.sites = delaunay.points
        self.bounds = bounds
        self.cells = Voronoi.buildCells(delaunay: delaunay, bounds: bounds)
    }

    /// The cell for site `i`.
    public func cell(_ i: Int) -> Shape { cells[i] }

    /// The area-weighted centroid of cell `i` — where Lloyd relaxation would move
    /// the site. Falls back to the site itself for an empty cell.
    public func centroid(_ i: Int) -> Vector2 {
        polygonCentroid(cells[i].contours.first?.points ?? []) ?? sites[i]
    }

    /// Lloyd's relaxation: move each site to its cell's centroid and re-tessellate,
    /// `iterations` times. Each pass evens the cells out toward a calmer, more
    /// uniform ("centroidal") tiling. Returns the relaxed sites — feed them back
    /// into a new `Voronoi` (or keep iterating) as you like.
    public func relaxed(iterations: Int = 1) -> [Vector2] {
        guard iterations > 0 else { return sites }
        var current = sites
        for _ in 0..<iterations {
            let diagram = Voronoi(sites: current, bounds: bounds)
            current = current.indices.map { i in
                clamp(diagram.centroid(i), to: bounds)
            }
        }
        return current
    }

    // MARK: - Cell construction

    private static func buildCells(delaunay: Delaunay, bounds: Rectangle) -> [Shape] {
        let sites = delaunay.points
        let box = [bounds.topLeft, bounds.topRight, bounds.bottomRight, bounds.bottomLeft]

        return sites.indices.map { i in
            let si = sites[i]
            // The Voronoi cell is the bounding box clipped by the perpendicular
            // bisector against each Delaunay neighbor — keep the half-plane closer
            // to si. Neighbors suffice (a cell is bounded only by its neighbors'
            // bisectors); fall back to every other site when adjacency is empty
            // (isolated, coincident, or fully collinear inputs).
            var ns = delaunay.neighbors(of: i)
            if ns.isEmpty { ns = sites.indices.filter { $0 != i } }

            var poly = box
            for j in ns {
                let sj = sites[j]
                let normal = sj - si
                let offset = ((si + sj) * 0.5).dot(normal)
                poly = clipHalfPlane(poly, normal: normal, offset: offset)
                if poly.count < 3 { break }
            }
            return Shape(poly, closed: true)
        }
    }
}

// MARK: - Sketch sugar

public extension Sketch {
    /// The Voronoi diagram of `sites`, clipped to `bounds` (the whole canvas by
    /// default). The typed `Voronoi` value — iterate `.cells` to fill or stroke
    /// each one in its own color.
    func voronoi(_ sites: [Vector2], in bounds: Rectangle? = nil) -> Voronoi {
        Voronoi(sites: sites, bounds: bounds ?? canvasRectangle)
    }

    /// The Delaunay triangulation of `points` — iterate `.triangles` for the mesh,
    /// or call `.voronoi(bounds:)` for the dual diagram.
    func delaunay(_ points: [Vector2]) -> Delaunay { Delaunay(points) }

    /// Draw every Voronoi cell of `sites` (clipped to `bounds`, the canvas by
    /// default) with the current `fill`/`stroke`. For per-cell color, iterate the
    /// `voronoi(_:in:)` value's `cells` instead.
    func drawVoronoi(_ sites: [Vector2], in bounds: Rectangle? = nil) {
        for cell in voronoi(sites, in: bounds).cells { drawShape(cell) }
    }

    /// Draw the Delaunay triangulation of `points` with the current `fill`/`stroke`
    /// (`noFill()` for a wireframe mesh).
    func drawDelaunay(_ points: [Vector2]) {
        for triangle in Delaunay(points).triangles { drawShape(triangle.shape) }
    }

    /// Lloyd-relax `sites` toward an even ("centroidal") spacing inside `bounds`
    /// (the canvas by default), `iterations` times. A convenience for
    /// `voronoi(_:in:).relaxed(iterations:)`.
    func lloyd(_ sites: [Vector2], in bounds: Rectangle? = nil, iterations: Int = 1) -> [Vector2] {
        voronoi(sites, in: bounds).relaxed(iterations: iterations)
    }

    /// The canvas as a `Rectangle` (origin at the top-left, full `width`×`height`).
    var canvasRectangle: Rectangle {
        Rectangle(x: 0, y: 0, width: width, height: height)
    }
}

// MARK: - Geometry helpers (file-private)

/// The circumcircle of three points, or `nil` when they're collinear.
private func circumcircleOf(_ a: Vector2, _ b: Vector2, _ c: Vector2) -> (center: Vector2, radiusSquared: Double)? {
    let ax = a.x, ay = a.y, bx = b.x, by = b.y, cx = c.x, cy = c.y
    let d = 2 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))
    if abs(d) < 1e-12 { return nil }
    let a2 = ax * ax + ay * ay
    let b2 = bx * bx + by * by
    let c2 = cx * cx + cy * cy
    let ux = (a2 * (by - cy) + b2 * (cy - ay) + c2 * (ay - by)) / d
    let uy = (a2 * (cx - bx) + b2 * (ax - cx) + c2 * (bx - ax)) / d
    let center = Vector2(ux, uy)
    return (center, center.distanceSquared(to: a))
}

/// Sutherland–Hodgman clip of a convex polygon to the half-plane
/// `p · normal <= offset` (the side that keeps the bisector's nearer site).
private func clipHalfPlane(_ poly: [Vector2], normal: Vector2, offset: Double) -> [Vector2] {
    guard poly.count >= 2 else { return [] }
    var out: [Vector2] = []
    out.reserveCapacity(poly.count + 1)
    for i in poly.indices {
        let cur = poly[i]
        let prev = poly[i == 0 ? poly.count - 1 : i - 1]
        let curIn = cur.dot(normal) <= offset
        let prevIn = prev.dot(normal) <= offset
        if curIn {
            if !prevIn { out.append(intersectLine(prev, cur, normal, offset)) }
            out.append(cur)
        } else if prevIn {
            out.append(intersectLine(prev, cur, normal, offset))
        }
    }
    return out
}

/// Where segment `a→b` crosses the line `p · normal = offset`.
private func intersectLine(_ a: Vector2, _ b: Vector2, _ normal: Vector2, _ offset: Double) -> Vector2 {
    let da = a.dot(normal), db = b.dot(normal)
    let denom = db - da
    guard abs(denom) > 1e-12 else { return a }
    return a.lerp(to: b, (offset - da) / denom)
}

/// The area-weighted centroid of a polygon, or `nil` for a degenerate one.
private func polygonCentroid(_ poly: [Vector2]) -> Vector2? {
    guard poly.count >= 3 else { return poly.centroid }
    var area = 0.0, cx = 0.0, cy = 0.0
    for i in poly.indices {
        let p = poly[i]
        let q = poly[(i + 1) % poly.count]
        let cross = p.x * q.y - q.x * p.y
        area += cross
        cx += (p.x + q.x) * cross
        cy += (p.y + q.y) * cross
    }
    area *= 0.5
    guard abs(area) > 1e-9 else { return poly.centroid }
    return Vector2(cx / (6 * area), cy / (6 * area))
}

/// Clamp a point into a rectangle.
private func clamp(_ p: Vector2, to r: Rectangle) -> Vector2 {
    Vector2(min(max(p.x, r.corner.x), r.corner.x + r.width),
            min(max(p.y, r.corner.y), r.corner.y + r.height))
}
