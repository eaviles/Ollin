import Foundation

/// Rebuild the surface a point cloud sampled: from scattered points alone
/// (a depth-camera room sweep, a scanned object, any generated sampling of a
/// form) back to a triangle `Mesh` of the surface they came from.
///
/// ```swift
/// // A swept room, fused by a WorldCloud:
/// let room = reconstructSurface(of: world.cloud, spacing: world.voxelSize * 2,
///                               orientedToward: cameraPath)
/// drawMesh(room)
/// ```
///
/// The method is the classic signed-distance reconstruction: a small plane is
/// fitted to every point's neighborhood, the planes are turned to agree on
/// which side is outside, and the surface is pulled out of the resulting
/// signed distance field by marching cubes. Two properties follow from it:
///
/// - **Holes are honest.** Where the cloud has no samples, the distance is
///   *undefined* rather than guessed, so an unscanned region stays an open
///   hole instead of growing a fictitious cap. `maxGap` is the dial: data gaps
///   smaller than it close, larger ones stay open, and `.infinity` treats the
///   cloud as a closed surface.
/// - **Orientation needs help only without a camera.** Pass the sensor
///   position(s) the cloud was seen from (`orientedToward:`, one per captured
///   frame or just a few along the sweep) and every plane turns toward the
///   cameras near it, which is robust even on thin walls. With no viewpoints
///   the orientation propagates point-to-point along a spanning tree of the
///   cloud, which works well on smooth single surfaces and can flip on thin
///   double-sided structure.
///
/// The reconstruction is deterministic given its inputs, and it is
/// setup-shaped CPU work: reconstruct once and keep the mesh. For skinning
/// points that are material rather than samples of a surface (a splash, a
/// blob), `particleSurface` is the simpler, rounder tool.
///
/// - Parameters:
///   - points: The sampled positions.
///   - spacing: The typical distance between neighboring samples, or nil to
///     estimate it from the cloud. A `WorldCloud` fuses at its `voxelSize`,
///     so pass that (or slightly more).
///   - resolution: Grid cells across the longest side of the cloud's bounds,
///     as in `isosurface`. Detail finer than the sampling cannot be
///     recovered, so past `bounds / spacing` it only costs.
///   - viewpoints: Positions the cloud was observed from (camera poses'
///     translations). Empty falls back to spanning-tree propagation.
///   - maxGap: How large a data gap still closes. nil derives it per point
///     from the local sampling density (roughly the neighborhood radius),
///     capped at a small multiple of `spacing` so a region nobody sampled
///     reads as a hole rather than as room to guess; `.infinity` closes
///     everything, for clouds known to sample a closed surface.
///   - neighbors: How many nearby samples fit each plane. More smooths noise
///     and bridges thin gaps; fewer preserves fine detail.
///   - keepingLargestComponent: Drop every disconnected piece but the largest
///     (by area). Scan noise tends to leave small floating shells; this is
///     the broom for them. It keeps exactly one body, so a real separate
///     object (a ball on a floor it never touches in the samples) goes out
///     with the noise: reach for it when the scan is one connected space.
public func reconstructSurface(of points: [Vector3],
                               spacing: Double? = nil,
                               resolution: Int = 96,
                               orientedToward viewpoints: [Vector3] = [],
                               maxGap: Double? = nil,
                               neighbors: Int = 16,
                               keepingLargestComponent: Bool = false) -> Mesh {
    guard points.count >= 4, resolution >= 1 else { return Mesh(positions: [], indices: []) }

    var lo = points[0], hi = points[0]
    for p in points {
        lo = Vector3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z))
        hi = Vector3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
    }
    let extent = hi - lo
    let longest = max(extent.x, max(extent.y, extent.z))
    guard longest > 0, longest.isFinite else { return Mesh(positions: [], indices: []) }

    let sampleSpacing = spacing ?? estimatedSpacing(of: points, longest: longest)
    guard sampleSpacing > 0, sampleSpacing.isFinite else { return Mesh(positions: [], indices: []) }

    // The resolution rule: the marching cell must stay below the validity
    // cutoff, or one cell straddles two different surfaces and their planes'
    // sign disagreement shreds the junction into cell-scale lumps. The usual
    // cause is a cloud whose bounds dwarf its interesting region.
    let cellSize = longest / Double(min(resolution, 512))
    if cellSize > sampleSpacing * 2 {
        print(String(format: "Ollin: reconstructSurface is marching %.3g-wide cells over samples spaced %.3g; detail below the cell is lost and junctions can smear. Raise resolution, or crop the cloud to the region of interest.",
                     cellSize, sampleSpacing))
    }

    // The samples, indexed for the k-neighborhoods and the validity test.
    let grid = PointGrid3(points: points, cellSize: sampleSpacing * 2)
    let k = min(max(neighbors, 4), points.count - 1)

    // One tangent plane per point: the neighborhood centroid and the fitted
    // normal, plus how far the neighborhood reaches (the k-th neighbor's
    // distance), which doubles as the local hole-closing cutoff.
    var centers = [Vector3](repeating: .zero, count: points.count)
    var normals = [Vector3](repeating: .zero, count: points.count)
    var reach = [Double](repeating: 0, count: points.count)
    for i in points.indices {
        let hood = grid.kNearest(k + 1, to: points[i])   // includes the point itself
        var centroid = Vector3.zero
        for j in hood { centroid += points[j] }
        centroid *= 1 / Double(hood.count)
        var xx = 0.0, xy = 0.0, xz = 0.0, yy = 0.0, yz = 0.0, zz = 0.0
        for j in hood {
            let d = points[j] - centroid
            xx += d.x * d.x; xy += d.x * d.y; xz += d.x * d.z
            yy += d.y * d.y; yz += d.y * d.z; zz += d.z * d.z
        }
        centers[i] = centroid
        normals[i] = smallestEigenvector(xx: xx, xy: xy, xz: xz, yy: yy, yz: yz, zz: zz)
        reach[i] = (points[hood[hood.count - 1]] - points[i]).length
    }

    if viewpoints.isEmpty {
        orientAlongSpanningTree(normals: &normals, centers: centers, grid: grid, k: k)
    } else {
        orientToward(viewpoints: viewpoints, normals: &normals, centers: centers)
    }

    // The signed distance: the nearest plane's height, valid only where its
    // foot point lands near an actual sample. Negated into the marching-cubes
    // convention (inside = field above the level).
    let centerGrid = PointGrid3(points: centers, cellSize: sampleSpacing * 2)
    let pad = sampleSpacing * 2 + 1.5 * longest / Double(resolution)
    let bounds = (min: lo - Vector3(pad, pad, pad), max: hi + Vector3(pad, pad, pad))

    // The derived per-point cutoff is capped at a small multiple of the global
    // spacing. Uncapped, the k-th-neighbor distance *inflates* exactly where
    // data is missing (an occlusion shadow's sparse rim reaches far), turning
    // the least-observed regions into the most permissive ones, and phantom
    // bowls grow around partially-observed objects. A region nobody sampled
    // should read as a hole.
    let gapCeiling = sampleSpacing * 3.5

    // A valid crossing can only sit within the gap cutoff of a sample (that is
    // the validity test), so any lattice point provably farther than that from
    // every sample answers "undefined" from one occupancy read instead of two
    // nearest-neighbor searches. Most of the grid is far from the surface, so
    // this is the difference between touching every sample region and ring-
    // searching the whole box. It cannot apply under `.infinity`, which
    // legitimately closes surfaces far from any sample.
    let bandRadius: Double? = {
        let slack = 3 * longest / Double(resolution)
        if let maxGap { return maxGap.isFinite ? maxGap + slack : nil }
        return gapCeiling + slack
    }()
    let band = bandRadius.map { DilatedOccupancy(points: points, radius: $0) }

    var mesh = partialIsosurface(at: 0, in: bounds, resolution: resolution, field: { p in
        if let band, !band.mayHoldSurface(near: p) { return nil }
        guard let i = centerGrid.nearest(to: p) else { return nil }
        let height = (p - centers[i]).dot(normals[i])
        let foot = p - normals[i] * height
        guard let j = grid.nearest(to: foot) else { return nil }
        let gap = maxGap ?? Swift.min(reach[j], gapCeiling)
        guard gap == .infinity || (foot - points[j]).lengthSquared <= gap * gap else { return nil }
        return -height
    })

    if keepingLargestComponent { mesh = largestComponent(of: mesh) }
    return mesh
}

/// `reconstructSurface` over a point cloud's positions.
public func reconstructSurface(of cloud: PointCloud,
                               spacing: Double? = nil,
                               resolution: Int = 96,
                               orientedToward viewpoints: [Vector3] = [],
                               maxGap: Double? = nil,
                               neighbors: Int = 16,
                               keepingLargestComponent: Bool = false) -> Mesh {
    reconstructSurface(of: cloud.points.map(\.position),
                       spacing: spacing, resolution: resolution,
                       orientedToward: viewpoints, maxGap: maxGap,
                       neighbors: neighbors,
                       keepingLargestComponent: keepingLargestComponent)
}

// MARK: - The near-surface band

/// A coarse boolean lattice answering one question in one array read: could
/// any sample lie within `radius` of this position? Cells are `radius` wide
/// and every sample marks its own cell plus the surrounding shell, so an
/// unmarked cell is a guarantee (no sample within a cell's width), while a
/// marked one just means "look properly".
private struct DilatedOccupancy {
    private let minCorner: Vector3
    private let cell: Double
    private let nx: Int, ny: Int, nz: Int
    private var marked: [Bool]

    init(points: [Vector3], radius: Double) {
        var lo = points.first ?? .zero, hi = lo
        for p in points {
            lo = Vector3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z))
            hi = Vector3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
        }
        cell = max(radius, 1e-12)
        // One spare cell each side so a dilated mark never clips at the wall.
        minCorner = lo - Vector3(cell, cell, cell)
        let extent = hi - minCorner
        nx = Int(extent.x / cell) + 2
        ny = Int(extent.y / cell) + 2
        nz = Int(extent.z / cell) + 2
        marked = [Bool](repeating: false, count: nx * ny * nz)
        for p in points {
            let i = Int((p.x - minCorner.x) / cell)
            let j = Int((p.y - minCorner.y) / cell)
            let k = Int((p.z - minCorner.z) / cell)
            for dk in -1 ... 1 {
                for dj in -1 ... 1 {
                    for di in -1 ... 1 {
                        let x = i + di, y = j + dj, z = k + dk
                        guard x >= 0, x < nx, y >= 0, y < ny, z >= 0, z < nz else { continue }
                        marked[(z * ny + y) * nx + x] = true
                    }
                }
            }
        }
    }

    func mayHoldSurface(near p: Vector3) -> Bool {
        let i = Int((p.x - minCorner.x) / cell)
        let j = Int((p.y - minCorner.y) / cell)
        let k = Int((p.z - minCorner.z) / cell)
        guard i >= 0, i < nx, j >= 0, j < ny, k >= 0, k < nz else { return false }
        return marked[(k * ny + j) * nx + i]
    }
}

// MARK: - Spacing

/// The typical nearest-neighbor distance, measured over an evenly strided
/// sample of the cloud (deterministic; no randomness).
private func estimatedSpacing(of points: [Vector3], longest: Double) -> Double {
    let probe = PointGrid3(points: points, cellSize: longest / 64)
    let stride = Swift.max(1, points.count / 2048)
    var total = 0.0
    var counted = 0
    var i = 0
    while i < points.count {
        let near = probe.kNearest(2, to: points[i])   // self and the nearest other
        if near.count == 2 {
            total += (points[near[1]] - points[i]).length
            counted += 1
        }
        i += stride
    }
    return counted > 0 ? total / Double(counted) : 0
}

// MARK: - Orientation

/// Turn every plane to face the cameras that saw it, by a distance-weighted
/// vote of the viewpoints rather than the nearest alone. The nearest camera
/// sees a terminator sample edge-on, so its dot with the plane is near zero
/// and the sign is noise; flipped planes there raise phantom curtains around
/// partially-observed objects. Cameras elsewhere along the sweep see the
/// same sample at a healthier angle and still know the answer, so the vote
/// settles the band. The weight falls as one over
/// distance to the fourth power, so a far camera can never outvote a near one
/// through a wall (the thin-wall case stays decided by proximity).
private func orientToward(viewpoints: [Vector3], normals: inout [Vector3], centers: [Vector3]) {
    // A long capture path votes over its 16 nearest poses; a handful of
    // viewpoints just all vote.
    let eyes = viewpoints.count > 32
        ? PointGrid3(points: viewpoints,
                     cellSize: Swift.max(spread(of: viewpoints) / 16, 1e-9))
        : nil
    for i in normals.indices {
        let c = centers[i]
        var vote = 0.0
        func cast(_ e: Vector3) {
            let d = e - c
            let d2 = Swift.max(d.lengthSquared, 1e-12)
            vote += d.dot(normals[i]) / (d2 * d2 * d2.squareRoot())
        }
        if let eyes {
            for e in eyes.kNearest(16, to: c) { cast(viewpoints[e]) }
        } else {
            for e in viewpoints { cast(e) }
        }
        if vote < 0 { normals[i] = normals[i] * -1 }
    }
}

private func spread(of points: [Vector3]) -> Double {
    guard let first = points.first else { return 0 }
    var lo = first, hi = first
    for p in points {
        lo = Vector3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z))
        hi = Vector3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
    }
    let e = hi - lo
    return max(e.x, max(e.y, e.z))
}

/// The pose-less fallback: make neighboring planes agree by propagating a
/// choice of side along a minimum spanning tree of the neighbor graph, edges
/// weighted `1 - |n_i . n_j|` so the propagation prefers flat ground and
/// crosses sharp creases last. Each connected piece seeds at its topmost
/// point, whose normal is turned upward.
private func orientAlongSpanningTree(normals: inout [Vector3], centers: [Vector3],
                                     grid: PointGrid3, k: Int) {
    let count = centers.count
    guard count > 1 else { return }

    // The neighbor graph, as deduplicated undirected pairs in a fixed order.
    var pairs: [(a: Int32, b: Int32)] = []
    pairs.reserveCapacity(count * k)
    for i in 0 ..< count {
        for j in grid.kNearest(k + 1, to: centers[i]) where j != i {
            pairs.append(i < j ? (Int32(i), Int32(j)) : (Int32(j), Int32(i)))
        }
    }
    pairs.sort { $0.a != $1.a ? $0.a < $1.a : $0.b < $1.b }

    // Kruskal over the deduplicated edges, cheapest disagreement first.
    var edges: [(w: Double, a: Int32, b: Int32)] = []
    edges.reserveCapacity(pairs.count)
    var previous: (a: Int32, b: Int32) = (-1, -1)
    for pair in pairs {
        guard pair != previous else { continue }
        previous = pair
        let w = 1 - abs(normals[Int(pair.a)].dot(normals[Int(pair.b)]))
        edges.append((w, pair.a, pair.b))
    }
    edges.sort { lhs, rhs in
        if lhs.w != rhs.w { return lhs.w < rhs.w }
        return lhs.a != rhs.a ? lhs.a < rhs.a : lhs.b < rhs.b
    }

    var parent = Array(0 ..< count)
    func root(_ x: Int) -> Int {
        var r = x
        while parent[r] != r { r = parent[r] }
        var c = x
        while parent[c] != r { let next = parent[c]; parent[c] = r; c = next }
        return r
    }

    var treeNeighbors = [[Int32]](repeating: [], count: count)
    for edge in edges {
        let ra = root(Int(edge.a)), rb = root(Int(edge.b))
        guard ra != rb else { continue }
        parent[ra] = rb
        treeNeighbors[Int(edge.a)].append(edge.b)
        treeNeighbors[Int(edge.b)].append(edge.a)
    }

    // One seed per connected piece: its topmost point (ties to the lower
    // index), turned to face up, then a depth-first walk flipping every
    // child that disagrees with its parent.
    var componentTop: [Int: Int] = [:]
    for i in 0 ..< count {
        let r = root(i)
        if let best = componentTop[r] {
            if centers[i].y > centers[best].y { componentTop[r] = i }
        } else {
            componentTop[r] = i
        }
    }

    var visited = [Bool](repeating: false, count: count)
    var stack: [Int32] = []
    for seed in componentTop.values.sorted() {
        guard !visited[seed] else { continue }
        if normals[seed].y < 0 { normals[seed] = normals[seed] * -1 }
        visited[seed] = true
        stack.append(Int32(seed))
        while let top = stack.popLast() {
            let node = Int(top)
            for next32 in treeNeighbors[node] {
                let next = Int(next32)
                guard !visited[next] else { continue }
                if normals[node].dot(normals[next]) < 0 {
                    normals[next] = normals[next] * -1
                }
                visited[next] = true
                stack.append(next32)
            }
        }
    }
}

// MARK: - Pieces

/// The eigenvector of the smallest eigenvalue of a symmetric 3x3 matrix, by
/// cyclic Jacobi rotations: small, deterministic, and robust for the
/// covariance matrices the plane fit produces.
private func smallestEigenvector(xx: Double, xy: Double, xz: Double,
                                 yy: Double, yz: Double, zz: Double) -> Vector3 {
    var a = (xx: xx, xy: xy, xz: xz, yy: yy, yz: yz, zz: zz)
    // Eigenvectors accumulate as the columns of v.
    var v = (Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))

    for _ in 0 ..< 16 {
        let off = a.xy * a.xy + a.xz * a.xz + a.yz * a.yz
        if off < 1e-24 * max(1, a.xx * a.xx + a.yy * a.yy + a.zz * a.zz) { break }
        for pivot in 0 ..< 3 {
            let (app, aqq, apq): (Double, Double, Double)
            switch pivot {
            case 0: (app, aqq, apq) = (a.xx, a.yy, a.xy)
            case 1: (app, aqq, apq) = (a.xx, a.zz, a.xz)
            default: (app, aqq, apq) = (a.yy, a.zz, a.yz)
            }
            guard abs(apq) > 1e-300 else { continue }
            let theta = 0.5 * atan2(2 * apq, aqq - app)
            let c = cos(theta), s = sin(theta)

            // Rotate the matrix and the accumulated basis in the pivot plane.
            switch pivot {
            case 0:
                let nxx = c * c * app - 2 * s * c * apq + s * s * aqq
                let nyy = s * s * app + 2 * s * c * apq + c * c * aqq
                let nxz = c * a.xz - s * a.yz
                let nyz = s * a.xz + c * a.yz
                a = (nxx, 0, nxz, nyy, nyz, a.zz)
                let c0 = v.0 * c - v.1 * s, c1 = v.0 * s + v.1 * c
                v = (c0, c1, v.2)
            case 1:
                let nxx = c * c * app - 2 * s * c * apq + s * s * aqq
                let nzz = s * s * app + 2 * s * c * apq + c * c * aqq
                let nxy = c * a.xy - s * a.yz
                let nyz = s * a.xy + c * a.yz
                a = (nxx, nxy, 0, a.yy, nyz, nzz)
                let c0 = v.0 * c - v.2 * s, c2 = v.0 * s + v.2 * c
                v = (c0, v.1, c2)
            default:
                let nyy = c * c * app - 2 * s * c * apq + s * s * aqq
                let nzz = s * s * app + 2 * s * c * apq + c * c * aqq
                let nxy = c * a.xy - s * a.xz
                let nxz = s * a.xy + c * a.xz
                a = (a.xx, nxy, nxz, nyy, 0, nzz)
                let c1 = v.1 * c - v.2 * s, c2 = v.1 * s + v.2 * c
                v = (v.0, c1, c2)
            }
        }
    }

    let smallest: Vector3
    if a.xx <= a.yy && a.xx <= a.zz { smallest = v.0 }
    else if a.yy <= a.zz { smallest = v.1 }
    else { smallest = v.2 }
    return smallest.lengthSquared > 0 ? smallest.normalized : Vector3(0, 1, 0)
}

/// Keep only the mesh's largest connected piece, by surface area. Scan noise
/// leaves small closed shells floating off the real surface; this removes
/// them without touching the survivor.
private func largestComponent(of mesh: Mesh) -> Mesh {
    let triangleCount = mesh.indices.count / 3
    guard triangleCount > 0 else { return mesh }

    var parent = Array(0 ..< mesh.positions.count)
    func root(_ x: Int) -> Int {
        var r = x
        while parent[r] != r { r = parent[r] }
        var c = x
        while parent[c] != r { let next = parent[c]; parent[c] = r; c = next }
        return r
    }
    for t in 0 ..< triangleCount {
        let a = Int(mesh.indices[t * 3]), b = Int(mesh.indices[t * 3 + 1]), c = Int(mesh.indices[t * 3 + 2])
        parent[root(b)] = root(a)
        parent[root(c)] = root(a)
    }

    var area: [Int: Double] = [:]
    for t in 0 ..< triangleCount {
        let a = mesh.positions[Int(mesh.indices[t * 3])]
        let b = mesh.positions[Int(mesh.indices[t * 3 + 1])]
        let c = mesh.positions[Int(mesh.indices[t * 3 + 2])]
        area[root(Int(mesh.indices[t * 3])), default: 0] += (b - a).cross(c - a).length * 0.5
    }
    guard let keep = area.max(by: { lhs, rhs in
        lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key
    })?.key else { return mesh }

    var remap = [Int32](repeating: -1, count: mesh.positions.count)
    var positions: [Vector3] = []
    var normals: [Vector3] = []
    var indices: [UInt32] = []
    let hasNormals = mesh.normals.count == mesh.positions.count
    for t in 0 ..< triangleCount {
        guard root(Int(mesh.indices[t * 3])) == keep else { continue }
        for corner in 0 ..< 3 {
            let old = Int(mesh.indices[t * 3 + corner])
            if remap[old] < 0 {
                remap[old] = Int32(positions.count)
                positions.append(mesh.positions[old])
                if hasNormals { normals.append(mesh.normals[old]) }
            }
            indices.append(UInt32(remap[old]))
        }
    }
    return hasNormals ? Mesh(positions: positions, normals: normals, indices: indices)
                      : Mesh(positions: positions, indices: indices)
}
