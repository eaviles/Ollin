import Foundation

/// Isosurfaces: the surface where a 3D scalar field crosses a level, built as
/// a `Mesh` by marching cubes, or by dual contouring where the field has
/// corners to keep. Give it any `(Vector3) -> Double` field (a sum
/// of metaballs, 3D noise, a distance function, your own math) and a level,
/// and back comes the skin of the region where the field runs above it: the
/// 3D reading of what `isolines` does in the plane.
///
/// ```swift
/// let blob = isosurface(at: 1, in: Box3(min: Vector3(-2, -2, -2), max: Vector3(2, 2, 2))) { p in
///     1 / (p - a).lengthSquared + 1 / (p - b).lengthSquared
/// }
/// drawMesh(blob)
/// ```
///
/// The surface encloses the region where the field is **greater** than
/// `level`, so its normals point down the gradient, out of that region. A
/// signed distance function runs the other way (negative inside), so mesh one
/// by negating it: `isosurface(at: 0, in: box) { -sdf($0) }`.
///
/// The mesh comes back welded (one vertex per crossed grid edge, shared by
/// every cell that touches it) with smooth normals read off the field's
/// gradient, and it is watertight wherever the surface stays inside `bounds`.
/// Where the surface runs out through a wall of `bounds` it is left open, the
/// way a contour that leaves its rectangle comes back open. Deterministic
/// given the field, and setup-shaped work: build the mesh once and draw it,
/// rather than re-marching every frame.

/// The surface of `field` at `level` inside `bounds`, as a triangle `Mesh`.
/// `method` picks how the crossings become triangles: marching cubes by
/// default, or dual contouring for a field with corners to keep.
///
/// The field is sampled on a grid of cubic cells, `resolution` of them across
/// the longest side of `bounds` (so the shorter sides get proportionally
/// fewer); raise it for finer detail, at cubically more field samples. Faces
/// where the surface could be joined two ways are settled by the asymptotic
/// decider, which reads only the four values on that face, so neighboring
/// cells always agree and the surface never cracks. Deterministic.
public func isosurface(at level: Double = 0,
                       in bounds: Box3,
                       resolution: Int = 48,
                       method: IsosurfaceMethod = .marchingCubes,
                       field: (Vector3) -> Double) -> Mesh {
    guard let grid = IsosurfaceGrid(bounds: bounds, resolution: resolution) else {
        return Mesh(positions: [], indices: [])
    }
    let values = grid.sample(field, level: level)
    switch method {
    case .marchingCubes:
        return grid.march(values: values)
    case .dualContouring:
        return grid.dualContour(values: values, field: field, level: level)
    }
}

/// How `isosurface` turns the sampled field into triangles.
public enum IsosurfaceMethod: Sendable, Equatable {
    /// One vertex on every crossed grid edge, placed by interpolating the two
    /// samples, and each cell's crossings stitched into its patch of surface.
    /// Cheap (the field is read once per lattice point) and smooth, and it
    /// rounds any corner of the field off to the size of a cell, since a
    /// vertex can only sit on an edge of the grid.
    case marchingCubes
    /// One vertex per cell, placed where the tangent planes through the
    /// cell's crossings agree, read from the field's own normals there, so a
    /// crease stays a crease and a corner lands on the corner whatever the
    /// resolution. Costs about a dozen field calls per crossing more, and
    /// shades a crease with one normal per side. Reach for it when the field
    /// has edges to keep: a box, a bored hole, a chamfer.
    case dualContouring
}

/// `isosurface` over a field that may decline to answer: where `field` returns
/// nil the surface is *undefined*, and every cell touching an undefined sample
/// is skipped rather than guessed at, leaving the mesh open there. This is
/// what lets a reconstruction report holes in its data as holes in the
/// surface. Internal, and named apart from `isosurface` on purpose: a same-name
/// overload differing only in the closure's return optionality makes every
/// public trailing-closure call ambiguous. The public entry points are
/// `isosurface` (total fields) and `reconstructSurface` (which builds its
/// field on this).
func partialIsosurface(at level: Double,
                       in bounds: Box3,
                       resolution: Int,
                       field: (Vector3) -> Double?) -> Mesh {
    guard let grid = IsosurfaceGrid(bounds: bounds, resolution: resolution) else {
        return Mesh(positions: [], indices: [])
    }
    var defined: [Bool] = []
    let values = grid.sample(field, level: level, defined: &defined)
    return grid.march(values: values, defined: defined)
}

// MARK: - The cube

/// A cube corner is a 3-bit number: bit 0 is x, bit 1 is y, bit 2 is z. Every
/// table below is built from that one convention.
enum IsosurfaceCube {

    /// The 12 edges as (low corner, high corner). The low corner is always the
    /// one carrying 0 in the axis the edge runs along, so it names the lattice
    /// point the edge hangs off, and that is what lets the (up to four) cells
    /// meeting on an edge agree on one identity for it.
    static let edges: [(low: Int, high: Int)] = [
        (0, 1), (2, 3), (4, 5), (6, 7),   // along x
        (0, 2), (1, 3), (4, 6), (5, 7),   // along y
        (0, 4), (1, 5), (2, 6), (3, 7),   // along z
    ]

    /// The axis an edge runs along: 0 = x, 1 = y, 2 = z.
    static func axis(of edge: Int) -> Int { edge / 4 }

    /// Which edge joins two corners, or -1 if they aren't neighbors. Indexed
    /// `a * 8 + b`, symmetric.
    static let edgeBetween: [Int] = {
        var table = [Int](repeating: -1, count: 64)
        for (index, e) in edges.enumerated() {
            table[e.low * 8 + e.high] = index
            table[e.high * 8 + e.low] = index
        }
        return table
    }()

    /// The six faces, each as its four corners walked counter-clockwise **as
    /// seen from outside the cube**. That orientation is what lets a face's
    /// contour be directed with the enclosed region on its left, which in turn
    /// is what makes the loops close and wind consistently. Flat rather than
    /// nested, so walking it in the march touches no reference counts.
    static let faceCorners: [Int] = [
        0, 4, 6, 2,   // -x
        1, 3, 7, 5,   // +x
        0, 1, 5, 4,   // -y
        2, 6, 7, 3,   // +y
        0, 2, 3, 1,   // -z
        4, 5, 7, 6,   // +z
    ]
}

// MARK: - The grid

/// The sampling lattice over `bounds`, and the march across it.
struct IsosurfaceGrid {

    let origin: Vector3      // the lattice's (0, 0, 0) corner
    let spacing: Double      // one cell, cubic
    let nx: Int, ny: Int, nz: Int   // cells per axis
    let sx: Int, sy: Int, sz: Int   // lattice points per axis (cells + 1)

    init?(bounds: Box3, resolution: Int) {
        let size = bounds.size
        let longest = bounds.longestSide
        guard longest.isFinite, longest > 0, resolution >= 1 else { return nil }

        let cells = min(resolution, 512)
        spacing = longest / Double(cells)
        nx = max(1, Int((size.x / spacing).rounded(.up)))
        ny = max(1, Int((size.y / spacing).rounded(.up)))
        nz = max(1, Int((size.z / spacing).rounded(.up)))
        sx = nx + 1; sy = ny + 1; sz = nz + 1

        // Cubic cells rarely tile the box exactly, so center the overshoot
        // rather than piling it against the far corner.
        let covered = Vector3(Double(nx), Double(ny), Double(nz)) * spacing
        origin = bounds.min - (covered - size) * 0.5
    }

    /// The lattice point at integer coordinates.
    func point(_ i: Int, _ j: Int, _ k: Int) -> Vector3 {
        origin + Vector3(Double(i), Double(j), Double(k)) * spacing
    }

    func latticeIndex(_ i: Int, _ j: Int, _ k: Int) -> Int { (k * sy + j) * sx + i }

    /// The field over the whole lattice, shifted so the surface sits at zero.
    /// Everything downstream tests `> 0` for "inside", so the level never has
    /// to be threaded through the march.
    func sample(_ field: (Vector3) -> Double, level: Double) -> [Double] {
        var values = [Double](repeating: 0, count: sx * sy * sz)
        var index = 0
        for k in 0 ..< sz {
            for j in 0 ..< sy {
                for i in 0 ..< sx {
                    values[index] = field(point(i, j, k)) - level
                    index += 1
                }
            }
        }
        return values
    }

    /// The partial-field sampling: nil answers record as undefined (and a
    /// placeholder 0 value the march never reads through a defined cell).
    func sample(_ field: (Vector3) -> Double?, level: Double,
                defined: inout [Bool]) -> [Double] {
        var values = [Double](repeating: 0, count: sx * sy * sz)
        defined = [Bool](repeating: false, count: sx * sy * sz)
        var index = 0
        for k in 0 ..< sz {
            for j in 0 ..< sy {
                for i in 0 ..< sx {
                    if let v = field(point(i, j, k)) {
                        values[index] = v - level
                        defined[index] = true
                    }
                    index += 1
                }
            }
        }
        return values
    }

    // MARK: The march

    func march(values: [Double], defined: [Bool]? = nil) -> Mesh {
        var positions: [Vector3] = []
        var normals: [Vector3] = []
        var indices: [UInt32] = []

        // One slot per lattice edge (three per lattice point, one per axis),
        // holding the welded vertex once some cell has needed it. A flat array
        // rather than a dictionary: the march then visits cells in a fixed
        // order and the output is byte-reproducible.
        var vertexAt = [Int32](repeating: -1, count: sx * sy * sz * 3)

        var corner = [Double](repeating: 0, count: 8)
        var crossing = [Int](repeating: -1, count: 12)   // local edge to welded vertex
        var next = [Int](repeating: -1, count: 12)       // local edge to local edge
        var order = [Int](repeating: 0, count: 4)        // one face's crossings, in perimeter order
        var loop: [Int] = []
        loop.reserveCapacity(12)

        for k in 0 ..< nz {
            for j in 0 ..< ny {
                for i in 0 ..< nx {
                    // Gather the eight corner values and the inside/outside mask.
                    // A cell touching an undefined sample is skipped whole: the
                    // surface there is unknown, not absent, and guessing at it
                    // is how a data hole would grow a fictitious cap.
                    var mask = 0
                    var known = true
                    for c in 0 ..< 8 {
                        let lattice = latticeIndex(i + (c & 1), j + ((c >> 1) & 1), k + ((c >> 2) & 1))
                        if let defined, !defined[lattice] { known = false; break }
                        let v = values[lattice]
                        corner[c] = v
                        if v > 0 { mask |= 1 << c }
                    }
                    guard known else { continue }
                    if mask == 0 || mask == 255 { continue }   // wholly out or wholly in

                    // Chain the six faces' contour segments into a permutation
                    // on the crossed edges.
                    for e in 0 ..< 12 { next[e] = -1; crossing[e] = -1 }
                    for face in 0 ..< 6 {
                        link(face: face, corner: corner, order: &order, into: &next)
                    }

                    // Follow that permutation: every cycle is one closed loop
                    // of the surface through this cell.
                    for start in 0 ..< 12 where next[start] >= 0 {
                        loop.removeAll(keepingCapacity: true)
                        var e = start
                        while next[e] >= 0 {
                            loop.append(e)
                            let step = next[e]
                            next[e] = -1
                            e = step
                        }
                        guard loop.count >= 3 else { continue }

                        // Weld each crossing, then emit. The loop runs with the
                        // enclosed region on its left seen from outside, which
                        // faces the triangles inward, so it is walked backwards.
                        for e in loop where crossing[e] < 0 {
                            crossing[e] = weld(edge: e, cell: (i, j, k), corner: corner,
                                               values: values, defined: defined,
                                               vertexAt: &vertexAt,
                                               positions: &positions, normals: &normals)
                        }
                        emit(loop: loop, crossing: crossing,
                             positions: &positions, normals: &normals, indices: &indices)
                    }
                }
            }
        }

        return Mesh(positions: positions, normals: normals, indices: indices)
    }

    /// One face's contribution: 0, 1, or 2 directed segments, recorded as
    /// `next[from] = to` over local edge indices. `order` is scratch the caller
    /// owns, so a face costs no allocation. Shared with the dual contouring,
    /// which chains the same segments to tell one sheet of surface through a
    /// cell from another, and which settles an ambiguous face through `decide`
    /// (given the face, whether its two inside corners join, or nil to fall
    /// back on the bilinear guess) by asking the field itself.
    func link(face: Int, corner: [Double], order: inout [Int], into next: inout [Int],
              decide: (Int) -> Bool? = { _ in nil }) {
        // Walk the face's perimeter counter-clockwise, collecting the sign
        // changes. A corner going inside to outside opens a segment; outside to
        // inside closes one, and because the signs alternate around the
        // perimeter, so do the two kinds.
        let base = face * 4
        var count = 0
        var opensFirst = false

        for step in 0 ..< 4 {
            let a = IsosurfaceCube.faceCorners[base + step], b = IsosurfaceCube.faceCorners[base + (step + 1) % 4]
            let inA = corner[a] > 0
            guard inA != (corner[b] > 0) else { continue }
            if count == 0 { opensFirst = inA }
            order[count] = IsosurfaceCube.edgeBetween[a * 8 + b]
            count += 1
        }

        switch count {
        case 2:
            let open = opensFirst ? 0 : 1
            next[order[open]] = order[1 - open]
        case 4:
            // The ambiguous face: two opposite corners inside, two outside, and
            // the contour can be drawn two ways. The asymptotic decider reads
            // the bilinear surface's saddle value, which depends only on these
            // four corner values, so the cell on the other side of this face
            // reaches the same answer and the two tessellations meet exactly.
            let joined = decide(face) ?? saddleIsInside(face: face, corner: corner)
            // Joining each open to the close that follows it cuts off the
            // outside corners, leaving the two inside ones connected; joining
            // it to the close before it separates them.
            for step in 0 ..< 4 where (step % 2 == 0) == opensFirst {
                next[order[step]] = order[joined ? (step + 1) % 4 : (step + 3) % 4]
            }
        default:
            break   // 0 crossings, or an odd count that sign changes can't produce
        }
    }

    /// Where the saddle of the face's bilinear surface sits, as the face's
    /// perimeter-corner offsets `(s, t)` from its first corner toward its
    /// second and its fourth, or nil when there is no saddle or it falls off
    /// the face. What the dual contouring asks the field at.
    func saddle(face: Int, corner: [Double]) -> (s: Double, t: Double)? {
        let base = face * 4
        let a = corner[IsosurfaceCube.faceCorners[base]], b = corner[IsosurfaceCube.faceCorners[base + 1]]
        let c = corner[IsosurfaceCube.faceCorners[base + 2]], d = corner[IsosurfaceCube.faceCorners[base + 3]]
        let denominator = a - b + c - d
        guard denominator != 0 else { return nil }
        let s = (a - d) / denominator, t = (a - b) / denominator
        guard s >= 0, s <= 1, t >= 0, t <= 1 else { return nil }
        return (s, t)
    }

    /// Whether the saddle of the face's bilinear surface sits inside. For
    /// corner values `a, b, c, d` walked around the face, the saddle value is
    /// `(a*c - b*d) / (a + c - b - d)`; the field is already shifted so the
    /// surface sits at zero, which makes its sign the whole answer.
    func saddleIsInside(face: Int, corner: [Double]) -> Bool {
        let base = face * 4
        let a = corner[IsosurfaceCube.faceCorners[base]], b = corner[IsosurfaceCube.faceCorners[base + 1]]
        let c = corner[IsosurfaceCube.faceCorners[base + 2]], d = corner[IsosurfaceCube.faceCorners[base + 3]]
        let denominator = a + c - b - d
        guard denominator != 0 else { return false }   // no saddle: keep them separate
        return (a * c - b * d) / denominator > 0
    }

    /// The welded vertex for a crossed edge of one cell, made on first use.
    private func weld(edge: Int, cell: (i: Int, j: Int, k: Int), corner: [Double],
                      values: [Double], defined: [Bool]?, vertexAt: inout [Int32],
                      positions: inout [Vector3], normals: inout [Vector3]) -> Int {
        let (low, high) = IsosurfaceCube.edges[edge]
        let axis = IsosurfaceCube.axis(of: edge)
        let li = cell.i + (low & 1), lj = cell.j + ((low >> 1) & 1), lk = cell.k + ((low >> 2) & 1)
        let slot = latticeIndex(li, lj, lk) * 3 + axis

        if vertexAt[slot] >= 0 { return Int(vertexAt[slot]) }

        // Where along the edge the field passes zero. The two ends straddle it,
        // so the denominator can't vanish.
        let a = corner[low], b = corner[high]
        let t = clamp(a / (a - b), 0, 1)

        var hi = (i: li, j: lj, k: lk)
        switch axis {
        case 0: hi.i += 1
        case 1: hi.j += 1
        default: hi.k += 1
        }

        let position = point(li, lj, lk) * (1 - t) + point(hi.i, hi.j, hi.k) * t
        // The normal is the field's own gradient, read off the samples already
        // taken and interpolated the way the position was, so a smooth field
        // gets a smooth surface at no extra field calls.
        let g = gradient(li, lj, lk, values, defined) * (1 - t)
              + gradient(hi.i, hi.j, hi.k, values, defined) * t
        let n = g.lengthSquared > 0 ? (g * -1).normalized : Vector3(0, 1, 0)

        let index = positions.count
        positions.append(position)
        normals.append(n)
        vertexAt[slot] = Int32(index)
        return index
    }

    /// The field's gradient at a lattice point by central differences, one-sided
    /// against the walls and against undefined samples (a nil `defined` makes
    /// every sample count as known, keeping the total-field path untouched).
    /// Unnormalized: the caller interpolates then normalizes.
    private func gradient(_ i: Int, _ j: Int, _ k: Int, _ values: [Double],
                          _ defined: [Bool]?) -> Vector3 {
        func slope(_ lo: Int, _ hi: Int, _ span: Int) -> Double {
            (values[hi] - values[lo]) / (Double(span) * spacing)
        }
        func known(_ index: Int) -> Bool { defined?[index] ?? true }
        let here = latticeIndex(i, j, k)
        let dx: Double
        if i > 0 && i < sx - 1 && known(here - 1) && known(here + 1) { dx = slope(here - 1, here + 1, 2) }
        else if i > 0 && known(here - 1) { dx = slope(here - 1, here, 1) }
        else if i < sx - 1 && known(here + 1) { dx = slope(here, here + 1, 1) }
        else { dx = 0 }

        let dy: Double
        if j > 0 && j < sy - 1 && known(here - sx) && known(here + sx) { dy = slope(here - sx, here + sx, 2) }
        else if j > 0 && known(here - sx) { dy = slope(here - sx, here, 1) }
        else if j < sy - 1 && known(here + sx) { dy = slope(here, here + sx, 1) }
        else { dy = 0 }

        let plane = sx * sy
        let dz: Double
        if k > 0 && k < sz - 1 && known(here - plane) && known(here + plane) { dz = slope(here - plane, here + plane, 2) }
        else if k > 0 && known(here - plane) { dz = slope(here - plane, here, 1) }
        else if k < sz - 1 && known(here + plane) { dz = slope(here, here + plane, 1) }
        else { dz = 0 }

        return Vector3(dx, dy, dz)
    }

    /// Triangulate one closed loop, walked backwards so the triangles face out.
    /// A triangle goes straight through; a quad splits on its shorter diagonal;
    /// anything larger fans from its own center, since a five- or six-sided
    /// loop through a cube is rarely flat and a corner fan would fold.
    private func emit(loop: [Int], crossing: [Int],
                      positions: inout [Vector3], normals: inout [Vector3],
                      indices: inout [UInt32]) {
        let v = loop.reversed().map { UInt32(crossing[$0]) }

        switch v.count {
        case 3:
            indices.append(contentsOf: v)
        case 4:
            let p = v.map { positions[Int($0)] }
            if (p[0] - p[2]).lengthSquared <= (p[1] - p[3]).lengthSquared {
                indices.append(contentsOf: [v[0], v[1], v[2], v[0], v[2], v[3]])
            } else {
                indices.append(contentsOf: [v[1], v[2], v[3], v[1], v[3], v[0]])
            }
        default:
            var center = Vector3.zero, normal = Vector3.zero
            for index in v {
                center += positions[Int(index)]
                normal += normals[Int(index)]
            }
            center *= 1 / Double(v.count)
            let hub = UInt32(positions.count)
            positions.append(center)
            normals.append(normal.lengthSquared > 0 ? normal.normalized : Vector3(0, 1, 0))
            for step in 0 ..< v.count {
                indices.append(contentsOf: [hub, v[step], v[(step + 1) % v.count]])
            }
        }
    }
}
