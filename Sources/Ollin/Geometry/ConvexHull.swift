import Foundation

/// The convex hull of a point set: the smallest convex polygon that contains
/// every point, like a rubber band snapped around them. Returns the hull's
/// corner points in order around the boundary (collinear points along an
/// edge are dropped, so every returned point is a true corner). Fewer than
/// three distinct points return what there is.
///
/// The hull is ordinary geometry: wrap it in a `Contour` or `Shape` to fill
/// it, stroke it, offset it, or hand it to the booleans.
///
/// ```swift
/// let band = convexHull(of: scatter)
/// noFill()
/// stroke(.white)
/// drawPolygon(band)
/// ```
public func convexHull(of points: [Vector2]) -> [Vector2] {
    // Sort by x, then y, dropping exact duplicates (the monotone-chain scan
    // needs a strict order).
    let sorted = Array(Set(points.map { HullPoint($0) })).sorted().map(\.point)
    guard sorted.count > 2 else { return sorted }

    // The turn direction of a→b→c (positive one way, negative the other);
    // zero means collinear.
    func cross(_ a: Vector2, _ b: Vector2, _ c: Vector2) -> Double {
        (b - a).cross(c - a)
    }

    var lower: [Vector2] = []
    for p in sorted {
        while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 {
            lower.removeLast()
        }
        lower.append(p)
    }

    var upper: [Vector2] = []
    for p in sorted.reversed() {
        while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 {
            upper.removeLast()
        }
        upper.append(p)
    }

    // Each chain's last point is the other's first; drop both to avoid
    // repeating the endpoints.
    return lower.dropLast() + upper.dropLast()
}

/// A hashable, orderable wrapper so the hull can deduplicate and sort points.
private struct HullPoint: Hashable, Comparable {
    let x: Double, y: Double
    var point: Vector2 { Vector2(x, y) }
    init(_ p: Vector2) { self.x = p.x; self.y = p.y }
    static func < (a: HullPoint, b: HullPoint) -> Bool {
        a.x != b.x ? a.x < b.x : a.y < b.y
    }
}

/// The convex hull of a point cloud in space: the smallest solid that contains
/// every point, the shape a balloon takes when it shrinks onto them.
///
/// It comes back as a `Mesh`, flat-shaded one normal per face, so it draws,
/// exports, and goes into a rigid body like any other mesh. Points inside the
/// hull are dropped, which makes this the way to turn a scan, a scatter, or a
/// model's vertices into a solid the eye and the solver can both work with.
///
/// ```swift
/// let solid = convexHull(of: cloud.positions)
/// material(.dielectric(roughness: 0.4))
/// drawMesh(solid)
/// ```
///
/// Fewer than four points, or points that all lie on one plane, enclose no
/// volume at all, so an empty mesh comes back.
public func convexHull(of points: [Vector3]) -> Mesh {
    let faces = convexHullFaces(of: points)
    guard !faces.isEmpty else { return Mesh(positions: [], indices: []) }
    var positions: [Vector3] = []
    var normals: [Vector3] = []
    var indices: [UInt32] = []
    positions.reserveCapacity(faces.count * 3)
    for face in faces {
        let normal = (face.1 - face.0).cross(face.2 - face.0).normalized
        let base = UInt32(positions.count)
        positions.append(contentsOf: [face.0, face.1, face.2])
        normals.append(contentsOf: [normal, normal, normal])
        indices.append(contentsOf: [base, base + 1, base + 2])
    }
    return Mesh(positions: positions, normals: normals, indices: indices)
}

/// The hull as outward-facing triangles, the shared core of `convexHull(of:)`
/// and the fracture path (which wants the face *planes* rather than a mesh).
///
/// The incremental construction: start from a tetrahedron of four points that
/// are as far from each other as the cloud allows, then take the rest one at a
/// time. A point outside the hull sees some faces; those faces go, and the
/// ring of edges around the hole they leave is joined to the new point.
func convexHullFaces(of points: [Vector3]) -> [(Vector3, Vector3, Vector3)] {
    guard points.count >= 4 else { return [] }
    guard let box = Box3(containing: points) else { return [] }
    let scale = Swift.max(box.longestSide, 1e-12)
    let epsilon = scale * 1e-9

    // Four points that enclose a real volume: the two farthest apart along an
    // axis, the one farthest off that line, and the one farthest off that plane.
    var first = 0
    for (i, p) in points.enumerated() where p.x < points[first].x { first = i }
    var second = first
    var span = 0.0
    for (i, p) in points.enumerated() {
        let d = p.distanceSquared(to: points[first])
        if d > span { span = d; second = i }
    }
    guard span > epsilon * epsilon else { return [] }
    let axis = (points[second] - points[first]).normalized
    var third = first
    var offLine = 0.0
    for (i, p) in points.enumerated() {
        let v = p - points[first]
        let d = (v - axis * v.dot(axis)).length
        if d > offLine { offLine = d; third = i }
    }
    guard offLine > epsilon else { return [] }
    let normal = (points[second] - points[first]).cross(points[third] - points[first]).normalized
    var fourth = first
    var offPlane = 0.0
    for (i, p) in points.enumerated() {
        let d = abs((p - points[first]).dot(normal))
        if d > offPlane { offPlane = d; fourth = i }
    }
    guard offPlane > epsilon else { return [] }

    var faces: [(Int, Int, Int)] = []
    let seed = [first, second, third, fourth]
    // Each of the tetrahedron's four faces, turned outward by testing it
    // against the one corner it does not carry.
    for skip in 0 ..< 4 {
        let tri = seed.enumerated().filter { $0.offset != skip }.map(\.element)
        let inside = points[seed[skip]]
        let a = points[tri[0]], b = points[tri[1]], c = points[tri[2]]
        let n = (b - a).cross(c - a)
        faces.append(n.dot(inside - a) > 0 ? (tri[0], tri[2], tri[1]) : (tri[0], tri[1], tri[2]))
    }

    func outwardNormal(_ face: (Int, Int, Int)) -> (Vector3, Vector3) {
        let a = points[face.0]
        return ((points[face.1] - a).cross(points[face.2] - a), a)
    }

    for (index, point) in points.enumerated() where !seed.contains(index) {
        // Which faces this point stands in front of. None means it is already
        // inside the hull and changes nothing.
        var visible: [Int] = []
        for (i, face) in faces.enumerated() {
            let (n, a) = outwardNormal(face)
            if n.dot(point - a) > epsilon * scale { visible.append(i) }
        }
        guard !visible.isEmpty else { continue }

        // The hole's rim: an edge of a visible face whose opposite edge belongs
        // to a face that stays, which is the boundary between what goes and
        // what remains. An edge is kept as one number so the lookup is a set
        // membership rather than a scan over every face.
        let gone = Set(visible)
        var edges = Set<Int>()
        let stride = points.count
        for i in visible {
            let face = faces[i]
            for edge in [(face.0, face.1), (face.1, face.2), (face.2, face.0)] {
                edges.insert(edge.0 * stride + edge.1)
            }
        }
        var rim: [(Int, Int)] = []
        for i in visible {
            let face = faces[i]
            for edge in [(face.0, face.1), (face.1, face.2), (face.2, face.0)]
            where !edges.contains(edge.1 * stride + edge.0) {
                rim.append(edge)
            }
        }
        guard !rim.isEmpty else { continue }
        faces = faces.enumerated().filter { !gone.contains($0.offset) }.map(\.element)
        for edge in rim { faces.append((edge.0, edge.1, index)) }
    }
    return faces.map { (points[$0.0], points[$0.1], points[$0.2]) }
}
