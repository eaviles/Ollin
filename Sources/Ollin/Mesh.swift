import Foundation
import simd

/// A solid 3D mesh: triangles in world-aware space, drawn through a `Camera3D`
/// with depth testing (see `Sketch.drawMesh`). It's the typed core the bare
/// primitive calls (`drawBox`, `drawSphere`, …) build on — each of those makes a
/// unit `Mesh` from a generator and draws it, positioned by the 3D transform
/// stack.
///
/// A mesh is plain geometry: `positions`, matching per-vertex `normals`, and a
/// triangle-list `indices` array (three indices per triangle). Build one with a
/// generator (`.box`, `.sphere`, `.cylinder`, `.plane`, `.torus`) or from your own
/// arrays. Generated primitives are centered at the origin and sized in world
/// units, so you place and orient them with `translate`/`rotate`/`scale` before
/// `drawMesh`.
///
/// Positions live in the camera's right-handed, y-up world space — *not* the 2D
/// canvas — so a mesh rides the camera and the 3D transform stack, not the 2D
/// affine. A primitive is cheap to rebuild each frame; for a dense generated
/// sphere you can also build the `Mesh` once and `drawMesh` it every frame.
public struct Mesh: Sendable {

    /// Vertex positions, world-aware (model units). Paired with `normals` by index.
    public var positions: [Vector3]
    /// Per-vertex outward normals, paired with `positions` by index. Used to color
    /// the surface today and to light it once the material model lands.
    public var normals: [Vector3]
    /// Triangle list: three indices into `positions`/`normals` per triangle.
    public var indices: [UInt32]

    /// A mesh from explicit arrays. `normals` should match `positions` by index
    /// (defaulting empty leaves the surface flat-normaled toward +z); `indices`
    /// are a triangle list (length a multiple of 3).
    public init(positions: [Vector3], normals: [Vector3] = [], indices: [UInt32]) {
        self.positions = positions
        self.normals = normals
        self.indices = indices
    }

    /// Number of triangles (index count ÷ 3).
    public var triangleCount: Int { indices.count / 3 }
    /// Whether the mesh has any triangles to draw.
    public var isEmpty: Bool { indices.isEmpty || positions.isEmpty }
}

// MARK: - Primitive generators

public extension Mesh {

    /// An axis-aligned box centered at the origin, `width` (x) × `height` (y) ×
    /// `depth` (z) world units, with one flat normal per face.
    static func box(width: Double, height: Double, depth: Double) -> Mesh {
        let hx = width / 2, hy = height / 2, hz = depth / 2
        // The eight corners, indexed by the sign of (x, y, z).
        let c: [Vector3] = [
            Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz), Vector3(hx, hy, -hz), Vector3(-hx, hy, -hz),
            Vector3(-hx, -hy, hz), Vector3(hx, -hy, hz), Vector3(hx, hy, hz), Vector3(-hx, hy, hz),
        ]
        var b = Builder()
        // Each face: four corners listed counter-clockwise as seen from outside,
        // and the face's outward normal.
        b.quad(c[4], c[5], c[6], c[7], normal: .unitZ)        // +z front
        b.quad(c[1], c[0], c[3], c[2], normal: -.unitZ)       // -z back
        b.quad(c[5], c[1], c[2], c[6], normal: .unitX)        // +x right
        b.quad(c[0], c[4], c[7], c[3], normal: -.unitX)       // -x left
        b.quad(c[7], c[6], c[2], c[3], normal: .unitY)        // +y top
        b.quad(c[0], c[1], c[5], c[4], normal: -.unitY)       // -y bottom
        return b.mesh()
    }

    /// A cube centered at the origin, `size` world units on each edge.
    static func box(size: Double = 1) -> Mesh { box(width: size, height: size, depth: size) }

    /// A UV sphere centered at the origin: `segments` divisions around the equator
    /// (longitude) and `rings` from pole to pole (latitude). Normals point radially
    /// outward.
    static func sphere(radius: Double = 0.5, segments: Int = 32, rings: Int = 16) -> Mesh {
        let segs = max(segments, 3), rng = max(rings, 2)
        var b = Builder()
        // A (rng+1) × (segs+1) grid of vertices, θ down from the +y pole, φ around y.
        for i in 0...rng {
            let theta = Double(i) / Double(rng) * .pi
            let st = sin(theta), ct = cos(theta)
            for j in 0...segs {
                let phi = Double(j) / Double(segs) * 2 * .pi
                let n = Vector3(st * cos(phi), ct, st * sin(phi))
                b.vertex(n * radius, normal: n)
            }
        }
        let stride = segs + 1
        for i in 0..<rng {
            for j in 0..<segs {
                let a = UInt32(i * stride + j)
                let bIdx = UInt32((i + 1) * stride + j)
                b.gridQuad(a, a + 1, bIdx + 1, bIdx)
            }
        }
        return b.mesh()
    }

    /// A cylinder centered at the origin, its axis along y, running from `-height/2`
    /// to `+height/2`. `segments` divisions around; `caps` closes the two ends with
    /// flat disks (on by default). Side normals point radially outward; cap normals
    /// point along ±y.
    static func cylinder(radius: Double = 0.5, height: Double = 1,
                         segments: Int = 32, caps: Bool = true) -> Mesh {
        let segs = max(segments, 3), hy = height / 2
        var b = Builder()
        // Side wall: a tube of quads, normals radial.
        let base = 0
        for j in 0...segs {
            let phi = Double(j) / Double(segs) * 2 * .pi
            let n = Vector3(cos(phi), 0, sin(phi))
            b.vertex(Vector3(n.x * radius, hy, n.z * radius), normal: n)   // top ring
            b.vertex(Vector3(n.x * radius, -hy, n.z * radius), normal: n)  // bottom ring
        }
        for j in 0..<segs {
            let top = UInt32(base + j * 2), bot = top + 1
            let topNext = top + 2, botNext = top + 3
            b.gridQuad(top, topNext, botNext, bot)
        }
        if caps {
            // Top cap: a fan around a center vertex, normal +y.
            let topCenter = b.addVertex(Vector3(0, hy, 0), normal: .unitY)
            let topStart = b.nextIndex
            for j in 0...segs {
                let phi = Double(j) / Double(segs) * 2 * .pi
                b.vertex(Vector3(cos(phi) * radius, hy, sin(phi) * radius), normal: .unitY)
            }
            for j in 0..<segs {
                b.triangle(topCenter, topStart + UInt32(j), topStart + UInt32(j) + 1)
            }
            // Bottom cap: a fan, normal -y, wound the other way so it faces down.
            let botCenter = b.addVertex(Vector3(0, -hy, 0), normal: -.unitY)
            let botStart = b.nextIndex
            for j in 0...segs {
                let phi = Double(j) / Double(segs) * 2 * .pi
                b.vertex(Vector3(cos(phi) * radius, -hy, sin(phi) * radius), normal: -.unitY)
            }
            for j in 0..<segs {
                b.triangle(botCenter, botStart + UInt32(j) + 1, botStart + UInt32(j))
            }
        }
        return b.mesh()
    }

    /// A flat plane centered at the origin in the x–z ground plane, `width` (x) ×
    /// `depth` (z) world units, its normal pointing up (+y). `segments` subdivides
    /// each axis (1 = a single quad). Drawn double-sided (no back-face culling), so
    /// it reads from above and below.
    static func plane(width: Double = 1, depth: Double = 1, segments: Int = 1) -> Mesh {
        let segs = max(segments, 1)
        var b = Builder()
        for i in 0...segs {
            let z = (Double(i) / Double(segs) - 0.5) * depth
            for j in 0...segs {
                let x = (Double(j) / Double(segs) - 0.5) * width
                b.vertex(Vector3(x, 0, z), normal: .unitY)
            }
        }
        let stride = segs + 1
        for i in 0..<segs {
            for j in 0..<segs {
                let a = UInt32(i * stride + j)
                let down = UInt32((i + 1) * stride + j)
                b.gridQuad(a, a + 1, down + 1, down)
            }
        }
        return b.mesh()
    }

    /// A torus (ring/doughnut) centered at the origin, lying in the x–z plane:
    /// `radius` from the center to the tube's center, `tube` the tube's own radius.
    /// `segments` divisions around the ring, `sides` around the tube.
    static func torus(radius: Double = 0.5, tube: Double = 0.2,
                      segments: Int = 48, sides: Int = 24) -> Mesh {
        let segs = max(segments, 3), sds = max(sides, 3)
        var b = Builder()
        for i in 0...segs {
            let a = Double(i) / Double(segs) * 2 * .pi
            let ca = cos(a), sa = sin(a)
            for j in 0...sds {
                let t = Double(j) / Double(sds) * 2 * .pi
                let ct = cos(t), stt = sin(t)
                let n = Vector3(ct * ca, stt, ct * sa)
                let p = Vector3((radius + tube * ct) * ca, tube * stt, (radius + tube * ct) * sa)
                b.vertex(p, normal: n)
            }
        }
        let stride = sds + 1
        for i in 0..<segs {
            for j in 0..<sds {
                let a = UInt32(i * stride + j)
                let next = UInt32((i + 1) * stride + j)
                b.gridQuad(a, a + 1, next + 1, next)
            }
        }
        return b.mesh()
    }

    /// A cone centered at the origin, its axis along y, the base disk at `-height/2`
    /// tapering to an apex at `+height/2`. `segments` divisions around; side normals
    /// follow the slanted wall, the base cap points down (−y).
    static func cone(radius: Double = 0.5, height: Double = 1, segments: Int = 32) -> Mesh {
        let segs = max(segments, 3), hy = height / 2
        var b = Builder()
        // The slanted-wall normal at longitude φ: radial, tilted up by the slope.
        func sideNormal(_ phi: Double) -> Vector3 {
            Vector3(height * cos(phi), radius, height * sin(phi)).normalized
        }
        for j in 0..<segs {
            let p0 = Double(j) / Double(segs) * 2 * .pi
            let p1 = Double(j + 1) / Double(segs) * 2 * .pi
            let i = b.nextIndex
            b.vertex(Vector3(cos(p0) * radius, -hy, sin(p0) * radius), normal: sideNormal(p0))
            b.vertex(Vector3(cos(p1) * radius, -hy, sin(p1) * radius), normal: sideNormal(p1))
            b.vertex(Vector3(0, hy, 0), normal: sideNormal((p0 + p1) / 2))
            b.triangle(i, i + 1, i + 2)
        }
        // Base cap: a fan, normal −y.
        let center = b.addVertex(Vector3(0, -hy, 0), normal: -.unitY)
        let start = b.nextIndex
        for j in 0...segs {
            let phi = Double(j) / Double(segs) * 2 * .pi
            b.vertex(Vector3(cos(phi) * radius, -hy, sin(phi) * radius), normal: -.unitY)
        }
        for j in 0..<segs {
            b.triangle(center, start + UInt32(j) + 1, start + UInt32(j))
        }
        return b.mesh()
    }

    /// A square-base pyramid centered at the origin, `width` (x) × `depth` (z) base
    /// at `-height/2` rising to an apex at `+height/2`. Faceted: four flat triangular
    /// sides plus a flat base.
    static func pyramid(width: Double = 1, depth: Double = 1, height: Double = 1) -> Mesh {
        let hx = width / 2, hz = depth / 2, hy = height / 2
        let apex = Vector3(0, hy, 0)
        let c0 = Vector3(-hx, -hy, -hz), c1 = Vector3(hx, -hy, -hz)
        let c2 = Vector3(hx, -hy, hz),  c3 = Vector3(-hx, -hy, hz)
        var b = Builder()
        b.triFlat(c0, c1, apex)   // four slanted faces, each its own flat normal
        b.triFlat(c1, c2, apex)
        b.triFlat(c2, c3, apex)
        b.triFlat(c3, c0, apex)
        b.polygonFlat([c0, c1, c2, c3])   // base (auto-oriented to face −y)
        return b.mesh()
    }

    /// A helix (coiled tube, like a spring), its axis along y. `turns` full coils
    /// over `height` world units; `radius` is the coil radius and `tube` the tube's
    /// own radius. `segments` samples the path, `sides` the tube cross-section.
    static func helix(radius: Double = 0.5, tube: Double = 0.12, turns: Double = 3,
                      height: Double = 1, segments: Int = 240, sides: Int = 12) -> Mesh {
        let n = max(segments, 8)
        let total = turns * 2 * .pi
        var path: [Vector3] = []
        path.reserveCapacity(n + 1)
        for i in 0...n {
            let f = Double(i) / Double(n)
            let a = f * total
            path.append(Vector3(cos(a) * radius, (f - 0.5) * height, sin(a) * radius))
        }
        return Mesh.tube(along: path, radius: tube, sides: sides, closed: false)
    }

    /// A regular icosahedron (20 triangular faces) centered at the origin, its
    /// vertices on a sphere of `radius`. Faceted (one flat normal per face).
    static func icosahedron(radius: Double = 0.5) -> Mesh {
        let v = Mesh.icosahedronVertices.map { $0 * radius }
        var b = Builder()
        for f in Mesh.icosahedronFaces {
            b.polygonFlat([v[f.0], v[f.1], v[f.2]])
        }
        return b.mesh()
    }

    /// A regular dodecahedron (12 pentagonal faces) centered at the origin, its
    /// vertices on a sphere of `radius`. Built as the dual of the icosahedron — its
    /// vertices are that solid's face centroids, its faces ring each of its vertices
    /// — so the connectivity is derived, not a hand-typed (error-prone) table.
    /// Faceted (one flat normal per pentagon).
    static func dodecahedron(radius: Double = 0.5) -> Mesh {
        let ico = Mesh.icosahedronVertices
        let faces = Mesh.icosahedronFaces
        // One dodecahedron vertex per icosahedron face: its (radial) centroid.
        let dodeca = faces.map { f -> Vector3 in
            ((ico[f.0] + ico[f.1] + ico[f.2]) / 3).normalized * radius
        }
        var b = Builder()
        // One dodecahedron face per icosahedron vertex: the ring of face-centroids
        // around it, ordered by angle in the plane perpendicular to the vertex.
        for vi in 0..<ico.count {
            var incident: [Int] = []
            for (fi, f) in faces.enumerated() where f.0 == vi || f.1 == vi || f.2 == vi {
                incident.append(fi)
            }
            guard incident.count >= 3 else { continue }
            let axis = ico[vi].normalized
            func projected(_ p: Vector3) -> Vector3 { p - axis * p.dot(axis) }
            let ref = projected(dodeca[incident[0]]).normalized
            let side = axis.cross(ref)
            let ordered = incident.sorted { a, c in
                let pa = projected(dodeca[a]), pc = projected(dodeca[c])
                return atan2(pa.dot(side), pa.dot(ref)) < atan2(pc.dot(side), pc.dot(ref))
            }
            b.polygonFlat(ordered.map { dodeca[$0] })
        }
        return b.mesh()
    }

    /// A (p, q) torus knot centered at the origin: a tube swept along the knot curve
    /// that winds `p` times around the axis and `q` times around the hole (coprime p,
    /// q give a true knot). `radius` sizes the knot, `tube` the tube's own radius.
    static func torusKnot(p: Int = 2, q: Int = 3, radius: Double = 0.5, tube: Double = 0.16,
                          segments: Int = 240, sides: Int = 14) -> Mesh {
        let n = max(segments, 16)
        var path: [Vector3] = []
        path.reserveCapacity(n)
        for i in 0..<n {     // closed loop — don't duplicate the last point
            let t = Double(i) / Double(n) * 2 * .pi
            let pt = Double(p) * t, qt = Double(q) * t
            let r = 2 + cos(qt)
            // Standard torus-knot curve, remapped so the winding axis is y (upright).
            path.append(Vector3(r * cos(pt), sin(qt), r * sin(pt)) * (radius / 3))
        }
        return Mesh.tube(along: path, radius: tube, sides: sides, closed: true)
    }
}

// MARK: - Swept tube + polyhedron data (internal — shared by the generators above)

private extension Mesh {

    /// Sweep a circular tube of `radius` along a polyline `path`, with `sides`
    /// around the cross-section. Uses a parallel-transport (rotation-minimizing)
    /// frame so the tube doesn't twist along the curve — the basis for `helix` and
    /// `torusKnot`. `closed` joins the last ring back to the first.
    static func tube(along path: [Vector3], radius: Double, sides: Int, closed: Bool) -> Mesh {
        let n = path.count
        guard n >= 2 else { return Mesh(positions: [], indices: []) }
        let sds = max(sides, 3)

        // Tangent at each point (central difference; wraps for a closed loop).
        var tangents = [Vector3](repeating: .unitZ, count: n)
        for i in 0..<n {
            let t: Vector3
            if closed {
                t = path[(i + 1) % n] - path[(i - 1 + n) % n]
            } else if i == 0 {
                t = path[1] - path[0]
            } else if i == n - 1 {
                t = path[n - 1] - path[n - 2]
            } else {
                t = path[i + 1] - path[i - 1]
            }
            tangents[i] = t.normalized
        }

        // Parallel-transport a normal along the curve.
        var normals = [Vector3](repeating: .zero, count: n)
        var binormals = [Vector3](repeating: .zero, count: n)
        var up = Vector3.unitY
        if abs(tangents[0].dot(up)) > 0.99 { up = .unitX }
        var nrm = tangents[0].cross(up).normalized
        normals[0] = nrm
        binormals[0] = tangents[0].cross(nrm).normalized
        for i in 1..<n {
            let t0 = tangents[i - 1], t1 = tangents[i]
            let axis = t0.cross(t1)
            let sinA = axis.length
            if sinA > 1e-8 {
                let angle = atan2(sinA, max(-1, min(1, t0.dot(t1))))
                nrm = rotate(nrm, around: axis / sinA, by: angle)
            }
            nrm = (nrm - t1 * nrm.dot(t1)).normalized   // keep it perpendicular to the tangent
            normals[i] = nrm
            binormals[i] = t1.cross(nrm).normalized
        }

        // On a closed loop the transported frame generally doesn't line up with
        // where it started (a "holonomy" twist), so the last ring meets the first
        // at a visible seam. Measure that mismatch and unwind it evenly along the
        // loop, so the frame closes smoothly. (Open curves have no seam to fix.)
        if closed, n > 2 {
            // Continue the transport across the closing segment (point n-1 → 0) and
            // measure the leftover angle between that frame and the starting normal,
            // in the plane perpendicular to the first tangent.
            var wrap = normals[n - 1]
            let axis = tangents[n - 1].cross(tangents[0])
            let s = axis.length
            if s > 1e-8 {
                wrap = rotate(wrap, around: axis / s, by: atan2(s, max(-1, min(1, tangents[n - 1].dot(tangents[0])))))
            }
            wrap = (wrap - tangents[0] * wrap.dot(tangents[0])).normalized
            let theta = atan2(wrap.dot(binormals[0]), wrap.dot(normals[0]))
            for i in 0..<n {
                let correction = -theta * Double(i) / Double(n)
                normals[i] = rotate(normals[i], around: tangents[i], by: correction)
                binormals[i] = tangents[i].cross(normals[i]).normalized
            }
        }

        var b = Builder()
        let stride = sds + 1
        for i in 0..<n {
            for j in 0...sds {
                let phi = Double(j) / Double(sds) * 2 * .pi
                let dir = normals[i] * cos(phi) + binormals[i] * sin(phi)
                b.vertex(path[i] + dir * radius, normal: dir)
            }
        }
        let rings = closed ? n : n - 1
        for i in 0..<rings {
            let a0 = i * stride, a1 = ((i + 1) % n) * stride
            for j in 0..<sds {
                b.gridQuad(UInt32(a0 + j), UInt32(a0 + j + 1),
                           UInt32(a1 + j + 1), UInt32(a1 + j))
            }
        }
        return b.mesh()
    }

    /// Rotate `v` around a unit `axis` by `angle` radians (Rodrigues' formula).
    static func rotate(_ v: Vector3, around axis: Vector3, by angle: Double) -> Vector3 {
        let c = cos(angle), s = sin(angle)
        return v * c + axis.cross(v) * s + axis * (axis.dot(v) * (1 - c))
    }

    /// The 12 icosahedron vertices (unit-ish, golden-ratio coordinates), normalized
    /// onto the unit sphere. The dodecahedron is built as this solid's dual.
    static let icosahedronVertices: [Vector3] = {
        let t = (1 + 5.0.squareRoot()) / 2   // golden ratio
        return [
            Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
            Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
            Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
        ].map { $0.normalized }
    }()

    /// The 20 icosahedron faces (vertex-index triples). Winding is fixed up by
    /// `polygonFlat` (which orients each face outward), so only the connectivity matters.
    static let icosahedronFaces: [(Int, Int, Int)] = [
        (0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11),
        (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
        (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9),
        (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1),
    ]
}

// MARK: - Builder (internal — accumulates a generator's geometry)

private struct Builder {
    var positions: [Vector3] = []
    var normals: [Vector3] = []
    var indices: [UInt32] = []

    /// The index the next appended vertex will take.
    var nextIndex: UInt32 { UInt32(positions.count) }

    mutating func vertex(_ p: Vector3, normal: Vector3) {
        positions.append(p)
        normals.append(normal)
    }

    /// Append a vertex and return its index.
    @discardableResult
    mutating func addVertex(_ p: Vector3, normal: Vector3) -> UInt32 {
        let i = nextIndex
        vertex(p, normal: normal)
        return i
    }

    mutating func triangle(_ a: UInt32, _ b: UInt32, _ c: UInt32) {
        indices.append(a); indices.append(b); indices.append(c)
    }

    /// Append a flat-shaded triangle (one face normal from the winding) as three
    /// new vertices — for faceted shapes like the pyramid.
    mutating func triFlat(_ a: Vector3, _ b: Vector3, _ c: Vector3) {
        let n = (b - a).cross(c - a).normalized
        let i = nextIndex
        vertex(a, normal: n); vertex(b, normal: n); vertex(c, normal: n)
        triangle(i, i + 1, i + 2)
    }

    /// Append a flat-shaded convex polygon as a triangle fan with one face normal,
    /// auto-oriented to face *away from the origin* (so an origin-centered solid's
    /// faces all point outward regardless of the input winding). For the regular
    /// polyhedra, where getting every face's winding right by hand is error-prone.
    mutating func polygonFlat(_ pts: [Vector3]) {
        guard pts.count >= 3 else { return }
        var ordered = pts
        var n = (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized
        let center = pts.reduce(Vector3.zero, +) / Double(pts.count)
        if n.dot(center) < 0 { ordered.reverse(); n = -n }
        let i = nextIndex
        for p in ordered { vertex(p, normal: n) }
        for k in 1..<(ordered.count - 1) {
            triangle(i, i + UInt32(k), i + UInt32(k) + 1)
        }
    }

    /// Two triangles over four existing vertex indices listed counter-clockwise.
    mutating func gridQuad(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32) {
        triangle(a, b, c); triangle(a, c, d)
    }

    /// Append four new vertices (all sharing `normal`) as a quad listed
    /// counter-clockwise from outside — for flat-faced shapes like the box.
    mutating func quad(_ a: Vector3, _ b: Vector3, _ c: Vector3, _ d: Vector3, normal: Vector3) {
        let i = nextIndex
        vertex(a, normal: normal); vertex(b, normal: normal)
        vertex(c, normal: normal); vertex(d, normal: normal)
        gridQuad(i, i + 1, i + 2, i + 3)
    }

    func mesh() -> Mesh { Mesh(positions: positions, normals: normals, indices: indices) }
}

// MARK: - Matrix helpers (internal — for baking the model transform CPU-side)

extension simd_float4x4 {
    /// The upper-left 3×3 (rotation + scale + shear), dropping translation.
    var upperLeft3x3: simd_float3x3 {
        simd_float3x3(columns: (
            SIMD3<Float>(columns.0.x, columns.0.y, columns.0.z),
            SIMD3<Float>(columns.1.x, columns.1.y, columns.1.z),
            SIMD3<Float>(columns.2.x, columns.2.y, columns.2.z)
        ))
    }

    /// The matrix that transforms normals: the inverse-transpose of the upper-left
    /// 3×3, correct under non-uniform scale (a plain 3×3 would skew normals when x,
    /// y, z scale differently).
    var normalMatrix: simd_float3x3 { upperLeft3x3.inverse.transpose }
}
