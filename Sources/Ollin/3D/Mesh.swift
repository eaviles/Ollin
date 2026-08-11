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
    /// Per-vertex texture coordinates (0,0 … 1,1), paired with `positions` by index.
    /// Empty (the default) leaves the mesh untextured; a textured `material` needs
    /// these to map (a count matching `positions`), else the surface draws flat in
    /// its base color. The built-in generators emit them where there's a natural
    /// parameterization (sphere, plane); a loaded model carries its own.
    public var uvs: [Vector2]
    /// Per-vertex surface colors, paired with `positions` by index. Empty (the
    /// default) leaves the surface in the current `fill` alone; a full, aligned
    /// set *multiplies* the fill per vertex (the texture contract), so with the
    /// default white fill the mesh shows its own colors untouched, and `fill`
    /// stays a whole-mesh tint. Set them directly, with `colored(by:)`, or with
    /// `colored(from:)` (a reconstructed cloud keeps its colors this way); a
    /// count that doesn't match `positions` is ignored. Lighting shades a vertex
    /// color exactly as it shades the fill; a wireframe (edges in the stroke
    /// color) ignores them.
    public var colors: [Color]
    /// The surface look — base color and optional texture — or `nil` for a plain
    /// surface drawn in the current `fill`. Set with `textured(_:)` or read from a
    /// model file. The texture maps through `uvs`.
    public var material: MeshMaterial?
    /// Per-vertex tangents, paired with `positions` by index: the surface's +u
    /// direction plus a bitangent handedness, the basis a normal map perturbs
    /// against. Empty (the default) for every mesh that doesn't need them; a
    /// normal-mapped material needs a full aligned set (the `uvs` rule) or the
    /// map is skipped with a note. `normalMapped(_:scale:)` and the model loaders
    /// fill them in (generated with MikkTSpace when the file authors none), or
    /// call `generatingTangents()` after a rebuild that dropped them.
    public var tangents: [MeshTangent]

    /// A mesh from explicit arrays. `normals` should match `positions` by index
    /// (defaulting empty leaves the surface flat-normaled toward +z); `indices`
    /// are a triangle list (length a multiple of 3); `uvs` and `colors`, when
    /// present, match `positions` by index.
    public init(positions: [Vector3], normals: [Vector3] = [], indices: [UInt32],
                uvs: [Vector2] = [], colors: [Color] = [], material: MeshMaterial? = nil,
                tangents: [MeshTangent] = []) {
        self.positions = positions
        self.normals = normals
        self.indices = indices
        self.uvs = uvs
        self.colors = colors
        self.material = material
        self.tangents = tangents
    }

    /// Number of triangles (index count ÷ 3).
    public var triangleCount: Int { indices.count / 3 }
    /// Whether the mesh has any triangles to draw.
    public var isEmpty: Bool { indices.isEmpty || positions.isEmpty }
}

// MARK: - Bounds & fit

public extension Mesh {

    /// The axis-aligned bounding box: the `min` and `max` corners over all
    /// `positions`. Returns `(.zero, .zero)` for an empty mesh. The generators are
    /// origin-centered, but a mesh loaded from a file arrives wherever its author
    /// placed it and at whatever scale: `bounds`, `center`, `size`, and
    /// `normalized(scale:)` are how you fit one to the canvas.
    var bounds: (min: Vector3, max: Vector3) {
        guard let first = positions.first else { return (.zero, .zero) }
        var lo = first, hi = first
        for p in positions {
            lo = Vector3(Swift.min(lo.x, p.x), Swift.min(lo.y, p.y), Swift.min(lo.z, p.z))
            hi = Vector3(Swift.max(hi.x, p.x), Swift.max(hi.y, p.y), Swift.max(hi.z, p.z))
        }
        return (lo, hi)
    }

    /// The center of the axis-aligned bounds (the midpoint of `bounds`).
    var center: Vector3 { let b = bounds; return (b.min + b.max) * 0.5 }

    /// The full extent of the axis-aligned bounds: its width (x), height (y), and
    /// depth (z) as a `Vector3`.
    var size: Vector3 { let b = bounds; return b.max - b.min }

    /// A copy recentered on the origin and uniformly scaled so its longest dimension
    /// spans `scale` world units. Turns an arbitrarily-placed, arbitrarily-sized
    /// loaded model into a drop-in unit mesh you position with the transform stack,
    /// the way the built-in generators already are. Normals are unchanged, a
    /// uniform scale preserves their direction.
    func normalized(scale: Double = 1) -> Mesh {
        let b = bounds
        let c = (b.min + b.max) * 0.5
        let s = b.max - b.min
        let longest = Swift.max(s.x, Swift.max(s.y, s.z))
        let factor = longest > 1e-12 ? scale / longest : 1
        return Mesh(positions: positions.map { ($0 - c) * factor },
                    normals: normals, indices: indices, uvs: uvs, colors: colors,
                    material: material, tangents: tangents)
    }

    /// A copy wearing `image` as its texture (tinted by `baseColor`, default white).
    /// The texture maps through the mesh's `uvs`, so use it on a mesh that carries
    /// them — a generator like `.sphere`/`.plane` or a loaded model — else the
    /// surface draws flat in `baseColor`. Mirrors `normalized(scale:)`: a value
    /// transform returning a new mesh.
    ///
    /// ```swift
    /// drawMesh(.sphere(radius: 200).textured(earthImage))
    /// ```
    func textured(_ image: Image, baseColor: Color = .white) -> Mesh {
        var copy = self
        // Keep an already-attached normal map: `textured` sets the color side of
        // the material, so `.normalMapped(bumps).textured(wood)` composes.
        var m = copy.material ?? MeshMaterial()
        m.baseColor = baseColor
        m.texture = image
        copy.material = m
        return copy
    }

    /// A copy with area-weighted smooth normals computed from the positions and
    /// triangle indices, replacing whatever normals it had. For a mesh built from raw
    /// geometry with no normals (a deforming face mesh, a marching-cubes surface) so it
    /// lights correctly.
    func withSmoothNormals() -> Mesh {
        var accum = [Vector3](repeating: .zero, count: positions.count)
        var i = 0
        while i + 2 < indices.count {
            let a = Int(indices[i]), b = Int(indices[i + 1]), c = Int(indices[i + 2])
            i += 3
            guard a < positions.count, b < positions.count, c < positions.count else { continue }
            let fn = (positions[b] - positions[a]).cross(positions[c] - positions[a])
            accum[a] = accum[a] + fn; accum[b] = accum[b] + fn; accum[c] = accum[c] + fn
        }
        var copy = self
        copy.normals = accum.map { $0.lengthSquared > 1e-12 ? $0.normalized : Vector3.unitY }
        return copy
    }
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
                // u wraps around (longitude), v runs pole to pole (latitude).
                let uv = Vector2(Double(j) / Double(segs), Double(i) / Double(rng))
                b.vertex(n * radius, normal: n, uv: uv)
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
            // Top cap: a fan around a center vertex, normal +y. Wound so its
            // triangles face the same way out of the solid as the wall's do:
            // the two caps and the wall have to agree, or the surface has no
            // consistent inside and anything reading the winding rather than
            // the normals (a soft body's springs, a subdivision cage) sees a
            // shape turned partly inside out.
            let topCenter = b.addVertex(Vector3(0, hy, 0), normal: .unitY)
            let topStart = b.nextIndex
            for j in 0...segs {
                let phi = Double(j) / Double(segs) * 2 * .pi
                b.vertex(Vector3(cos(phi) * radius, hy, sin(phi) * radius), normal: .unitY)
            }
            for j in 0..<segs {
                b.triangle(topCenter, topStart + UInt32(j) + 1, topStart + UInt32(j))
            }
            // Bottom cap: a fan, normal -y, wound the other way so it too faces
            // out of the solid rather than into it.
            let botCenter = b.addVertex(Vector3(0, -hy, 0), normal: -.unitY)
            let botStart = b.nextIndex
            for j in 0...segs {
                let phi = Double(j) / Double(segs) * 2 * .pi
                b.vertex(Vector3(cos(phi) * radius, -hy, sin(phi) * radius), normal: -.unitY)
            }
            for j in 0..<segs {
                b.triangle(botCenter, botStart + UInt32(j), botStart + UInt32(j) + 1)
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
            let v = Double(i) / Double(segs)
            let z = (v - 0.5) * depth
            for j in 0...segs {
                let u = Double(j) / Double(segs)
                let x = (u - 0.5) * width
                b.vertex(Vector3(x, 0, z), normal: .unitY, uv: Vector2(u, v))
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
            // Wound out of the solid, matching the normals the sides already
            // carry, so the cone has a consistent inside for anything reading
            // its triangles rather than its normals.
            b.triangle(i, i + 2, i + 1)
        }
        // Base cap: a fan, normal −y, wound out of the solid the same way.
        let center = b.addVertex(Vector3(0, -hy, 0), normal: -.unitY)
        let start = b.nextIndex
        for j in 0...segs {
            let phi = Double(j) / Double(segs) * 2 * .pi
            b.vertex(Vector3(cos(phi) * radius, -hy, sin(phi) * radius), normal: -.unitY)
        }
        for j in 0..<segs {
            b.triangle(center, start + UInt32(j), start + UInt32(j) + 1)
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
        // Four slanted faces, each its own flat normal. Wound so the normal the
        // winding gives points out of the solid: `triFlat` takes the face's
        // normal from the order of its corners, so the corners going round the
        // other way would light every slope from inside the pyramid.
        b.triFlat(c1, c0, apex)
        b.triFlat(c2, c1, apex)
        b.triFlat(c3, c2, apex)
        b.triFlat(c0, c3, apex)
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

    /// A regular tetrahedron (4 triangular faces) centered at the origin, vertices
    /// on a sphere of `radius`. Faceted.
    static func tetrahedron(radius: Double = 0.5) -> Mesh {
        let v = [Vector3(1, 1, 1), Vector3(1, -1, -1), Vector3(-1, 1, -1), Vector3(-1, -1, 1)]
            .map { $0.normalized * radius }
        var b = Builder()
        for f in [(0, 1, 2), (0, 3, 1), (0, 2, 3), (1, 3, 2)] {
            b.polygonFlat([v[f.0], v[f.1], v[f.2]])
        }
        return b.mesh()
    }

    /// A regular octahedron (8 triangular faces) centered at the origin, vertices on
    /// a sphere of `radius`. Faceted.
    static func octahedron(radius: Double = 0.5) -> Mesh {
        let v = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0),
                 Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)].map { $0 * radius }
        var b = Builder()
        for f in [(0, 2, 4), (2, 1, 4), (1, 3, 4), (3, 0, 4),
                  (2, 0, 5), (1, 2, 5), (3, 1, 5), (0, 3, 5)] {
            b.polygonFlat([v[f.0], v[f.1], v[f.2]])
        }
        return b.mesh()
    }

    /// A capsule (a cylinder with hemispherical caps) centered at the origin, its
    /// axis along y. `height` is the length of the straight cylindrical section
    /// (total height is `height + 2·radius`). `segments` divisions around, `rings`
    /// latitude bands per hemisphere. Normals are radial from the nearer cap center.
    static func capsule(radius: Double = 0.4, height: Double = 0.8,
                        segments: Int = 32, rings: Int = 8) -> Mesh {
        let segs = max(segments, 3), rng = max(rings, 1), hy = height / 2
        var b = Builder()
        // Ring list: top hemisphere (offset +hy) then bottom (offset −hy). The two
        // equator rings (one per hemisphere) bound the cylinder wall between them.
        var rowOffsets: [(theta: Double, yOffset: Double)] = []
        for i in 0...rng { rowOffsets.append((Double(i) / Double(rng) * .pi / 2, hy)) }
        for i in 0...rng { rowOffsets.append((.pi / 2 + Double(i) / Double(rng) * .pi / 2, -hy)) }
        for row in rowOffsets {
            let st = sin(row.theta), ct = cos(row.theta)
            for j in 0...segs {
                let phi = Double(j) / Double(segs) * 2 * .pi
                let n = Vector3(st * cos(phi), ct, st * sin(phi))
                b.vertex(Vector3(n.x * radius, n.y * radius + row.yOffset, n.z * radius), normal: n)
            }
        }
        let stride = segs + 1
        for i in 0..<(rowOffsets.count - 1) {
            for j in 0..<segs {
                let a = UInt32(i * stride + j)
                let down = UInt32((i + 1) * stride + j)
                b.gridQuad(a, a + 1, down + 1, down)
            }
        }
        return b.mesh()
    }

    /// A box with rounded edges and corners centered at the origin, `width` (x) ×
    /// `height` (y) × `depth` (z), the edges filleted by `radius`. `segments` is the
    /// per-face grid resolution (higher = smoother rounding). Built by pushing each
    /// point of a subdivided cube out from an inset core by `radius` (the signed-
    /// distance rounded-box surface), so flat faces stay flat and edges curve.
    static func roundedBox(width: Double = 1, height: Double = 1, depth: Double = 1,
                           radius: Double = 0.15, segments: Int = 20) -> Mesh {
        let hx = width / 2, hy = height / 2, hz = depth / 2
        let r = min(radius, min(hx, min(hy, hz)))
        let inner = Vector3(hx - r, hy - r, hz - r)
        let segs = max(segments, 1)
        func clampAbs(_ v: Double, _ m: Double) -> Double { min(max(v, -m), m) }
        var b = Builder()
        // Each face: a (segs+1)² grid over the two tangent axes, pushed out from the
        // inset core. `axis` is the face's outward unit, `uAxis`/`vAxis` span it.
        // The two span axes are listed so that `uAxis × vAxis` is the face's own
        // outward direction, which is what makes every quad below come out wound
        // the same way round the solid; listed the other way, half the faces
        // wind inward and the box has no consistent inside.
        let faces: [(axis: Vector3, uAxis: Vector3, vAxis: Vector3, uh: Double, vh: Double)] = [
            (.unitX, .unitY, .unitZ, hy, hz), (-.unitX, .unitZ, .unitY, hz, hy),
            (.unitY, .unitZ, .unitX, hz, hx), (-.unitY, .unitX, .unitZ, hx, hz),
            (.unitZ, .unitX, .unitY, hx, hy), (-.unitZ, .unitY, .unitX, hy, hx),
        ]
        for face in faces {
            let base = b.nextIndex
            let center = face.axis * (abs(face.axis.x) * hx + abs(face.axis.y) * hy + abs(face.axis.z) * hz)
            for iv in 0...segs {
                let v = (Double(iv) / Double(segs) * 2 - 1) * face.vh
                for iu in 0...segs {
                    let u = (Double(iu) / Double(segs) * 2 - 1) * face.uh
                    let p = center + face.uAxis * u + face.vAxis * v
                    let q = Vector3(clampAbs(p.x, inner.x), clampAbs(p.y, inner.y), clampAbs(p.z, inner.z))
                    let dir = p - q
                    let len = dir.length
                    let n = len > 1e-6 ? dir / len : face.axis
                    b.vertex(q + n * r, normal: n)
                }
            }
            let stride = segs + 1
            for iv in 0..<segs {
                for iu in 0..<segs {
                    let a = base + UInt32(iv * stride + iu)
                    let down = base + UInt32((iv + 1) * stride + iu)
                    b.gridQuad(a, a + 1, down + 1, down)
                }
            }
        }
        return b.mesh()
    }

    /// A rounded cube `size` on each edge, edges filleted by `radius`.
    static func roundedBox(size: Double, radius: Double = 0.15, segments: Int = 20) -> Mesh {
        roundedBox(width: size, height: size, depth: size, radius: radius, segments: segments)
    }

    /// A geodesic sphere built by subdividing an icosahedron `subdivisions` times and
    /// projecting onto a sphere of `radius` — evenly sized triangles with no pole
    /// pinching (unlike the UV `sphere`). Smooth (radial) normals.
    static func icosphere(radius: Double = 0.5, subdivisions: Int = 2) -> Mesh {
        var tris: [(Vector3, Vector3, Vector3)] = Mesh.icosahedronFaces.map {
            (Mesh.icosahedronVertices[$0.0], Mesh.icosahedronVertices[$0.1], Mesh.icosahedronVertices[$0.2])
        }
        for _ in 0..<max(subdivisions, 0) {
            var next: [(Vector3, Vector3, Vector3)] = []
            next.reserveCapacity(tris.count * 4)
            for t in tris {
                let ab = ((t.0 + t.1) * 0.5).normalized
                let bc = ((t.1 + t.2) * 0.5).normalized
                let ca = ((t.2 + t.0) * 0.5).normalized
                next.append((t.0, ab, ca))
                next.append((ab, t.1, bc))
                next.append((ca, bc, t.2))
                next.append((ab, bc, ca))
            }
            tris = next
        }
        var b = Builder()
        for t in tris {
            let i = b.nextIndex
            b.vertex(t.0 * radius, normal: t.0)
            b.vertex(t.1 * radius, normal: t.1)
            b.vertex(t.2 * radius, normal: t.2)
            b.triangle(i, i + 1, i + 2)
        }
        return b.mesh()
    }

    /// A Möbius strip — a band with a half-twist, the classic one-sided surface.
    /// `radius` is the loop radius, `width` the band's width. `segments` around the
    /// loop, `sides` across the band.
    static func mobius(radius: Double = 0.5, width: Double = 0.3,
                       segments: Int = 140, sides: Int = 12) -> Mesh {
        Mesh.parametricSurface(uSteps: segments, vSteps: sides, uClosed: false, vClosed: false) { uu, vv in
            let phi = uu * 2 * .pi
            let t = (vv - 0.5) * width
            let r = radius + t * cos(phi / 2)
            return Vector3(r * cos(phi), t * sin(phi / 2), r * sin(phi))
        }
    }

    /// A Klein bottle (the figure-8 immersion) centered at the origin — a closed,
    /// one-sided surface. `scale` sizes it; `segments`/`sides` set the grid density.
    static func klein(scale: Double = 0.22, segments: Int = 100, sides: Int = 40) -> Mesh {
        Mesh.parametricSurface(uSteps: segments, vSteps: sides, uClosed: true, vClosed: true) { uu, vv in
            let u = uu * 2 * .pi, v = vv * 2 * .pi, half = uu * .pi
            let common = 2 + cos(half) * sin(v) - sin(half) * sin(2 * v)
            let x = common * cos(u)
            let y = common * sin(u)
            let z = sin(half) * sin(v) + cos(half) * sin(2 * v)
            return Vector3(x, z, y) * scale   // remap so the bottle stands upright (y up)
        }
    }

    /// A superellipsoid centered at the origin: a sphere (`e1 = e2 = 1`) that morphs
    /// toward a box (`e → 0`) or an octahedron (`e → 2`) as the exponents change.
    /// `e1` shapes it pole-to-pole, `e2` around the equator. A generative-art toy.
    static func superellipsoid(radius: Double = 0.5, e1: Double = 0.5, e2: Double = 0.5,
                               segments: Int = 64, rings: Int = 32) -> Mesh {
        func sp(_ base: Double, _ e: Double) -> Double {
            (base < 0 ? -1.0 : 1.0) * pow(abs(base), e)
        }
        return Mesh.parametricSurface(uSteps: segments, vSteps: rings, uClosed: true, vClosed: false) { uu, vv in
            let omega = (uu - 0.5) * 2 * .pi
            let eta = (vv - 0.5) * .pi
            let ce = sp(cos(eta), e1)
            return Vector3(radius * ce * sp(cos(omega), e2),
                           radius * sp(sin(eta), e1),
                           radius * ce * sp(sin(omega), e2))
        }
    }

    /// A 3D supershape (Gielis superformula) centered at the origin — a handful of
    /// parameters sweep through an enormous range of organic, star, and flower-like
    /// forms. `m` sets the symmetry (lobe count); `n1`/`n2`/`n3` shape the lobes.
    /// `m = 0, n* = 1` is a sphere. The same superformula shapes both latitude and
    /// longitude. Great driven by `time` or a `@Param`.
    static func supershape(radius: Double = 0.5, m: Double = 7, n1: Double = 0.2,
                           n2: Double = 1.7, n3: Double = 1.7,
                           segments: Int = 120, rings: Int = 60) -> Mesh {
        func sf(_ angle: Double) -> Double {
            let t = m * angle / 4
            let denom = pow(abs(cos(t)), n2) + pow(abs(sin(t)), n3)
            guard denom > 1e-9, abs(n1) > 1e-9 else { return 0 }
            let r = pow(denom, -1 / n1)
            return r.isFinite ? min(r, 4) : 0
        }
        return Mesh.parametricSurface(uSteps: segments, vSteps: rings, uClosed: true, vClosed: false) { uu, vv in
            let phi = (uu - 0.5) * 2 * .pi
            let theta = (vv - 0.5) * .pi
            let r1 = sf(phi), r2 = sf(theta)
            return Vector3(radius * r1 * cos(phi) * r2 * cos(theta),
                           radius * r2 * sin(theta),
                           radius * r1 * sin(phi) * r2 * cos(theta))
        }
    }

    /// Extrude a closed 2D outline (in the x–y plane) into a solid `depth` deep
    /// along z, centered on z = 0 — a flat shape pushed into 3D. The front and back
    /// faces come from triangulating the outline (so any shape works, including the
    /// `Profile` helpers); the side walls connect the two. See the `Shape` overload
    /// for holed shapes.
    static func extrude(_ outline: [Vector2], depth: Double = 0.5) -> Mesh {
        extrude(Shape(outline, closed: true), depth: depth)
    }

    /// Extrude a 2D `Shape` (in the x–y plane) into a solid `depth` deep along z,
    /// centered on z = 0. Honors the shape's fill rule and holes — the caps come
    /// from `Shape.triangulatedFill()`, and a wall is raised along every closed
    /// contour (outer boundary and holes alike). The bridge from Ollin's 2D vector
    /// geometry (`Path`, the shape booleans, the `Profile` helpers) into 3D.
    static func extrude(_ shape: Shape, depth: Double = 0.5) -> Mesh {
        let hz = depth / 2
        var b = Builder()
        // Front (+z) and back (−z) caps from the triangulated fill.
        let tris = shape.triangulatedFill()
        var k = 0
        while k + 2 < tris.count {
            let a = tris[k], bb = tris[k + 1], c = tris[k + 2]
            b.triangleFlatZ(a, bb, c, z: hz, normal: .unitZ)
            b.triangleFlatZ(a, c, bb, z: -hz, normal: -.unitZ)
            k += 3
        }
        // Side walls along each closed contour.
        for contour in shape.contours where contour.isClosed && contour.points.count >= 2 {
            let pts = contour.points
            for e in 0..<pts.count {
                let p0 = pts[e], p1 = pts[(e + 1) % pts.count]
                let f0 = Vector3(p0.x, p0.y, hz), f1 = Vector3(p1.x, p1.y, hz)
                let k0 = Vector3(p0.x, p0.y, -hz), k1 = Vector3(p1.x, p1.y, -hz)
                var n = (k0 - f0).cross(f1 - f0)
                n = n.lengthSquared > 1e-12 ? n.normalized : .unitX
                let i = b.nextIndex
                b.vertex(f0, normal: n); b.vertex(f1, normal: n)
                b.vertex(k1, normal: n); b.vertex(k0, normal: n)
                // Round the wall the way `n` already faces, so the side agrees
                // with the two caps about which way is out of the solid.
                b.gridQuad(i, i + 3, i + 2, i + 1)
            }
        }
        return b.mesh()
    }

    /// Revolve a 2D `silhouette` around the y-axis to build a surface of revolution
    /// — a vase, bowl, goblet, or lamp from its side profile. Each point's `x` is its
    /// distance from the axis (≥ 0) and `y` its height; `segments` is the number of
    /// divisions around. Normals come from the silhouette's own slope, rotated.
    static func lathe(_ silhouette: [Vector2], segments: Int = 48) -> Mesh {
        let rows = silhouette.count
        guard rows >= 2 else { return Mesh(positions: [], indices: []) }
        let segs = max(segments, 3)
        func sNormal(_ j: Int) -> Vector2 {
            let t = silhouette[min(j + 1, rows - 1)] - silhouette[max(j - 1, 0)]
            let perp = Vector2(t.y, -t.x)
            return perp.length > 1e-9 ? perp.normalized : Vector2(1, 0)
        }
        var b = Builder()
        for i in 0...segs {
            let phi = Double(i) / Double(segs) * 2 * .pi
            let c = cos(phi), s = sin(phi)
            for j in 0..<rows {
                let p = silhouette[j], sn = sNormal(j)
                b.vertex(Vector3(p.x * c, p.y, p.x * s),
                         normal: Vector3(sn.x * c, sn.y, sn.x * s).normalized)
            }
        }
        for i in 0..<segs {
            for j in 0..<(rows - 1) {
                let a = UInt32(i * rows + j), down = UInt32((i + 1) * rows + j)
                b.gridQuad(a, a + 1, down + 1, down)
            }
        }
        return b.mesh()
    }
}

/// Closed 2D outlines for `Mesh.extrude` / `drawExtrude` — the same flat shapes a
/// 2D tool offers (rectangle, ellipse, triangle, polygon, star), centered at the
/// origin in the x–y plane and wound counter-clockwise. Each returns a point list,
/// so you can also feed your own.
public enum Profile {
    /// An axis-aligned rectangle, `width` × `height`.
    public static func rectangle(width: Double = 1, height: Double = 1) -> [Vector2] {
        let hx = width / 2, hy = height / 2
        return [Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy), Vector2(-hx, hy)]
    }

    /// An ellipse with the given radii, sampled into `segments` points.
    public static func ellipse(radiusX: Double = 0.5, radiusY: Double = 0.5, segments: Int = 48) -> [Vector2] {
        let n = max(segments, 3)
        return (0..<n).map {
            let a = Double($0) / Double(n) * 2 * .pi
            return Vector2(cos(a) * radiusX, sin(a) * radiusY)
        }
    }

    /// An upward-pointing isosceles triangle, `width` wide and `height` tall.
    public static func triangle(width: Double = 1, height: Double = 1) -> [Vector2] {
        let hx = width / 2, hy = height / 2
        return [Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(0, hy)]
    }

    /// A regular polygon with `sides` sides on a circle of `radius`.
    public static func polygon(sides: Int = 6, radius: Double = 0.5) -> [Vector2] {
        let n = max(sides, 3)
        return (0..<n).map {
            let a = Double($0) / Double(n) * 2 * .pi + .pi / 2
            return Vector2(cos(a) * radius, sin(a) * radius)
        }
    }

    /// A star with `points` points alternating between `outerRadius` and `innerRadius`.
    public static func star(points: Int = 5, outerRadius: Double = 0.5, innerRadius: Double = 0.22) -> [Vector2] {
        let p = max(points, 2)
        return (0..<(p * 2)).map {
            let a = Double($0) / Double(p * 2) * 2 * .pi + .pi / 2
            let r = $0 % 2 == 0 ? outerRadius : innerRadius
            return Vector2(cos(a) * r, sin(a) * r)
        }
    }
}

// MARK: - Swept tube + polyhedron data (shared by the generators above)

extension Mesh {

    /// Sweep a circular tube of `radius` along a polyline `path`, with `sides`
    /// around the cross-section — the basis for `helix` and `torusKnot`, and a
    /// general way to thicken any 3D curve (a `PointCloud`-style path, a sampled
    /// `Path`) into a solid. Uses a parallel-transport (rotation-minimizing) frame
    /// so the tube doesn't twist along the curve; `closed` joins the last ring back
    /// to the first and unwinds the loop's holonomy so there's no seam.
    public static func tube(along path: [Vector3], radius: Double = 0.1,
                            sides: Int = 12, closed: Bool = false) -> Mesh {
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

    /// Build a quad-meshed surface from a `(u, v) → position` function over a grid,
    /// with per-vertex normals from central differences (so any parametric surface —
    /// Möbius, Klein, superellipsoid, supershape — drops in as a closure). `u`/`v`
    /// run 0…1; `uClosed`/`vClosed` wrap that axis (no duplicate seam row) and feed
    /// the difference across the wrap, so a closed surface has smooth normals.
    static func parametricSurface(uSteps: Int, vSteps: Int, uClosed: Bool, vClosed: Bool,
                                  _ f: (Double, Double) -> Vector3) -> Mesh {
        let uN = max(uSteps, 3), vN = max(vSteps, 2)
        let uCount = uClosed ? uN : uN + 1
        let vCount = vClosed ? vN : vN + 1
        var pos = [Vector3](repeating: .zero, count: uCount * vCount)
        for i in 0..<uCount {
            let u = Double(i) / Double(uN)
            for j in 0..<vCount { pos[i * vCount + j] = f(u, Double(j) / Double(vN)) }
        }
        func at(_ i: Int, _ j: Int) -> Vector3 {
            let ii = uClosed ? ((i % uCount) + uCount) % uCount : min(max(i, 0), uCount - 1)
            let jj = vClosed ? ((j % vCount) + vCount) % vCount : min(max(j, 0), vCount - 1)
            return pos[ii * vCount + jj]
        }
        var b = Builder()
        for i in 0..<uCount {
            for j in 0..<vCount {
                let du = at(i + 1, j) - at(i - 1, j)
                let dv = at(i, j + 1) - at(i, j - 1)
                // `dv × du`, not the other way round: the quads below are wound
                // along +v and then +u, so this is the direction their own
                // winding faces. Taking the other order shades every surface
                // built here from the side the light is not on.
                let cross = dv.cross(du)
                b.vertex(pos[i * vCount + j], normal: cross.lengthSquared > 1e-12 ? cross.normalized : .unitY)
            }
        }
        let uQuads = uClosed ? uCount : uCount - 1
        let vQuads = vClosed ? vCount : vCount - 1
        for i in 0..<uQuads {
            let i1 = uClosed ? (i + 1) % uCount : i + 1
            for j in 0..<vQuads {
                let j1 = vClosed ? (j + 1) % vCount : j + 1
                b.gridQuad(UInt32(i * vCount + j), UInt32(i * vCount + j1),
                           UInt32(i1 * vCount + j1), UInt32(i1 * vCount + j))
            }
        }
        return b.mesh()
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
    /// Texture coordinates, appended only by the `uv:`-taking `vertex`. A generator
    /// that never passes a UV leaves this empty, so `mesh()` ships no `uvs`; one
    /// that passes a UV for *every* vertex ships a full, aligned set.
    var uvs: [Vector2] = []

    /// The index the next appended vertex will take.
    var nextIndex: UInt32 { UInt32(positions.count) }

    mutating func vertex(_ p: Vector3, normal: Vector3) {
        positions.append(p)
        normals.append(normal)
    }

    /// Append a vertex carrying a texture coordinate. Use it for *every* vertex of
    /// a generator that emits UVs (sphere, plane), so `uvs` stays aligned with
    /// `positions`.
    mutating func vertex(_ p: Vector3, normal: Vector3, uv: Vector2) {
        positions.append(p)
        normals.append(normal)
        uvs.append(uv)
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

    /// Append a triangle from three 2D points placed at depth `z` (the x–y plane),
    /// all sharing `normal` — for the flat caps of an extrusion.
    mutating func triangleFlatZ(_ a: Vector2, _ b: Vector2, _ c: Vector2, z: Double, normal: Vector3) {
        let i = nextIndex
        vertex(Vector3(a.x, a.y, z), normal: normal)
        vertex(Vector3(b.x, b.y, z), normal: normal)
        vertex(Vector3(c.x, c.y, z), normal: normal)
        triangle(i, i + 1, i + 2)
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

    func mesh() -> Mesh {
        // Ship UVs only when one was supplied for every vertex (sphere/plane); a
        // partial set would mismap, so an unaligned count drops to untextured.
        Mesh(positions: positions, normals: normals, indices: indices,
             uvs: uvs.count == positions.count ? uvs : [])
    }
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
