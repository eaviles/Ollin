import Foundation

/// Scattering points over the surface of a mesh: an even covering of the skin
/// itself, rather than of the vertices that happen to describe it. This is what
/// puts props on a landscape, roots on a scalp, holes in a shell, and points in
/// a cloud made from geometry.
///
/// Scattering over the vertices is the tempting shortcut, and it is wrong for
/// every one of those: a mesh puts its vertices where the *shape* needs them, so
/// a flat wall carries four and a rounded corner carries hundreds. Points picked
/// from that list crowd the corner and leave the wall bare. Points picked over
/// the surface land at a rate set by area alone, which is what the eye reads as
/// even.
///
/// ```swift
/// let rocks = surfacePoints(on: ground, count: 400)
/// drawMesh(rock, instances: rocks.map {
///     MeshInstance(position: $0.position, rotation: $0.alignment(), scale: 0.2)
/// })
/// ```
///
/// Two spreads are offered. `.blueNoise` (the default) keeps a distance between
/// neighbors, so nothing clumps and nothing leaves a hole; `.random` is the
/// plain area-weighted draw, which is cheaper and clumps the way a handful of
/// thrown seed does. Both draw from `rng`, so a seed makes the layout repeat.
///
/// Each point comes back as a ``SurfaceSample``, which carries the surface it
/// landed on and not only the spot: the normal to stand a prop up, the texture
/// coordinate to read a picture at that spot, and the triangle and its corner
/// weights to interpolate anything else the mesh holds per vertex.

// MARK: - The sample

/// One point picked on a mesh's surface, with what the surface knows there.
public struct SurfaceSample: Sendable, Equatable {

    /// Where the point sits, in the mesh's own coordinates.
    public var position: Vector3

    /// Which way the surface faces at that point: the vertex normals blended
    /// across the triangle when the mesh carries them, else the triangle's own
    /// flat normal. Always unit length.
    public var normal: Vector3

    /// The texture coordinate there, blended across the triangle, or
    /// `Vector2.zero` when the mesh carries none.
    public var uv: Vector2

    /// Which triangle the point landed on. Multiply by three for the offset of
    /// its first corner in the mesh's `indices`.
    public var triangle: Int

    /// How much of each corner the point takes, the three weights adding to 1.
    /// Use them to blend any other per-vertex value the mesh holds.
    public var barycentric: Vector3

    /// A sample from its parts. You rarely build one; `surfacePoints` does.
    public init(position: Vector3, normal: Vector3, uv: Vector2,
                triangle: Int, barycentric: Vector3) {
        self.position = position
        self.normal = normal
        self.uv = uv
        self.triangle = triangle
        self.barycentric = barycentric
    }
}

/// How scattered points relate to each other.
public enum SurfaceScatter: Sendable, Hashable {
    /// Even spacing: no clumps and no bare patches, the arrangement the eye
    /// reads as a fair covering. It costs an oversampled draw and a pass that
    /// thins it down, so it is a few times the work of `.random`.
    case blueNoise
    /// A plain draw, each point placed with no regard for the ones before it.
    /// Cheapest, and it clumps: the natural look for thrown seed or splatter.
    case random
}

// MARK: - Area

public extension Mesh {

    /// The area of the skin: every triangle's area added up, in the square of
    /// the mesh's own units. Degenerate triangles contribute nothing.
    ///
    /// It is what turns a spacing into a count (an even covering at spacing `s`
    /// holds about `2 * area / (sqrt(3) * s * s)` points) and what sets the
    /// distance `.blueNoise` aims to keep.
    var surfaceArea: Double {
        var total = 0.0
        var i = 0
        while i + 2 < indices.count {
            let a = Int(indices[i]), b = Int(indices[i + 1]), c = Int(indices[i + 2])
            i += 3
            guard a < positions.count, b < positions.count, c < positions.count else { continue }
            total += ollinTriangleArea(positions[a], positions[b], positions[c])
        }
        return total
    }
}

/// Half the length of the cross product: the area of one triangle.
@inline(__always)
private func ollinTriangleArea(_ a: Vector3, _ b: Vector3, _ c: Vector3) -> Double {
    (b - a).cross(c - a).length * 0.5
}

// MARK: - Sampling

/// `count` points scattered over `mesh`, spread evenly by area rather than by
/// vertex: a triangle twice the size of its neighbor receives about twice as
/// many, whatever either one cost in vertices.
///
/// ```swift
/// var rng = SplitMix64(seed: 7)
/// let seeds = surfacePoints(on: terrain, count: 500, using: &rng)
/// drawMesh(tree, instances: seeds.map {
///     MeshInstance(position: $0.position, rotation: $0.alignment(), scale: 0.3)
/// })
/// ```
///
/// `.blueNoise` (the default) also keeps the points apart from each other. It
/// draws several times `count` candidates and thins them down, so ask for what
/// you want rather than trimming the result yourself: thinning is the step that
/// makes the spacing even, and cutting the list afterward undoes it.
///
/// - Parameters:
///   - mesh: The surface to cover. Its triangles are read in place; nothing is
///     rebuilt or welded first, so a seam between two triangles is not a seam
///     to the sampler.
///   - count: How many points to return. A mesh with no area returns none.
///   - scatter: Even spacing (`.blueNoise`) or a plain draw (`.random`).
///   - rng: The random source; seed it for a layout that repeats.
/// - Returns: The samples, in the order they were drawn.
public func surfacePoints<R: RandomNumberGenerator>(
    on mesh: Mesh,
    count: Int,
    scatter: SurfaceScatter = .blueNoise,
    using rng: inout R
) -> [SurfaceSample] {
    guard count > 0 else { return [] }
    let table = SurfaceAreaTable(mesh)
    guard table.total > 0 else { return [] }

    switch scatter {
    case .random:
        return table.draw(count, from: mesh, using: &rng)
    case .blueNoise:
        // Yuksel's thinning wants a few times the wanted count to choose from:
        // fewer leaves it no room to be picky, many more only costs time.
        let candidates = table.draw(count * blueNoiseOversample, from: mesh, using: &rng)
        return thinToBlueNoise(candidates, count: count, area: table.total)
    }
}

/// Points scattered over `mesh` at a target `spacing`: the count follows from
/// the area, the way `poissonDisk` takes a radius rather than a count.
///
/// `spacing` is the distance a point keeps from its neighbors under
/// `.blueNoise`. Under `.random` it only sets how many points are drawn, since
/// a plain draw keeps no distance from anything.
///
/// - Parameters:
///   - mesh: The surface to cover.
///   - spacing: The wanted distance between neighboring points, in the mesh's
///     own units.
///   - scatter: Even spacing (`.blueNoise`) or a plain draw (`.random`).
///   - rng: The random source; seed it for a layout that repeats.
/// - Returns: The samples, in the order they were drawn.
public func surfacePoints<R: RandomNumberGenerator>(
    on mesh: Mesh,
    spacing: Double,
    scatter: SurfaceScatter = .blueNoise,
    using rng: inout R
) -> [SurfaceSample] {
    guard spacing > 0 else { return [] }
    let count = surfacePointCount(area: mesh.surfaceArea, spacing: spacing)
    return surfacePoints(on: mesh, count: count, scatter: scatter, using: &rng)
}

/// How many points at `spacing` cover `area`, from the tightest arrangement
/// circles of that spacing can take (the honeycomb, which packs one point per
/// `sqrt(3) / 2 * spacing * spacing`).
func surfacePointCount(area: Double, spacing: Double) -> Int {
    guard area > 0, spacing > 0 else { return 0 }
    return Int((area * 2 / (3.0.squareRoot() * spacing * spacing)).rounded())
}

/// How many candidates a `.blueNoise` request draws per point it returns.
private let blueNoiseOversample = 5

// MARK: - Picking a triangle by area

/// The running total of triangle areas, which turns one number in `0 ..< total`
/// into a triangle chosen in proportion to its area.
private struct SurfaceAreaTable {

    /// `cumulative[t]` is the area of triangles `0 ... t`.
    private var cumulative: [Double] = []
    /// The corner indices of each triangle that has area.
    private var corners: [(Int, Int, Int)] = []
    /// Where each kept triangle sits in the mesh's own triangle numbering.
    private var number: [Int] = []

    var total: Double { cumulative.last ?? 0 }

    init(_ mesh: Mesh) {
        var running = 0.0
        var i = 0, t = 0
        cumulative.reserveCapacity(mesh.triangleCount)
        corners.reserveCapacity(mesh.triangleCount)
        number.reserveCapacity(mesh.triangleCount)
        while i + 2 < mesh.indices.count {
            let a = Int(mesh.indices[i]), b = Int(mesh.indices[i + 1]), c = Int(mesh.indices[i + 2])
            i += 3
            defer { t += 1 }
            guard a < mesh.positions.count, b < mesh.positions.count, c < mesh.positions.count else { continue }
            let area = ollinTriangleArea(mesh.positions[a], mesh.positions[b], mesh.positions[c])
            guard area > 0 else { continue }
            running += area
            cumulative.append(running)
            corners.append((a, b, c))
            number.append(t)
        }
    }

    /// The triangle holding `u`, which the caller draws in `0 ..< total`.
    private func triangle(at u: Double) -> Int {
        var lo = 0, hi = cumulative.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if cumulative[mid] <= u { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// `count` samples drawn over the whole surface.
    func draw<R: RandomNumberGenerator>(_ count: Int, from mesh: Mesh,
                                        using rng: inout R) -> [SurfaceSample] {
        guard count > 0, !cumulative.isEmpty else { return [] }
        var out: [SurfaceSample] = []
        out.reserveCapacity(count)
        for _ in 0 ..< count {
            let t = triangle(at: Double.random(in: 0 ..< total, using: &rng))
            let u = Double.random(in: 0 ..< 1, using: &rng)
            let v = Double.random(in: 0 ..< 1, using: &rng)
            out.append(sample(t, u, v, from: mesh))
        }
        return out
    }

    /// One sample in triangle `t`, from two numbers in `0 ..< 1`.
    private func sample(_ t: Int, _ u: Double, _ v: Double, from mesh: Mesh) -> SurfaceSample {
        let (ia, ib, ic) = corners[t]
        let bary = ollinTriangleBarycentric(u, v)
        let pa = mesh.positions[ia], pb = mesh.positions[ib], pc = mesh.positions[ic]
        let position = pa * bary.x + pb * bary.y + pc * bary.z

        var normal: Vector3
        if ia < mesh.normals.count, ib < mesh.normals.count, ic < mesh.normals.count {
            normal = mesh.normals[ia] * bary.x + mesh.normals[ib] * bary.y + mesh.normals[ic] * bary.z
        } else {
            normal = .zero
        }
        if normal.lengthSquared <= 1e-18 {
            normal = (pb - pa).cross(pc - pa)
        }
        normal = normal.lengthSquared > 1e-18 ? normal.normalized : .unitY

        var uv = Vector2.zero
        if ia < mesh.uvs.count, ib < mesh.uvs.count, ic < mesh.uvs.count {
            uv = mesh.uvs[ia] * bary.x + mesh.uvs[ib] * bary.y + mesh.uvs[ic] * bary.z
        }

        return SurfaceSample(position: position, normal: normal, uv: uv,
                             triangle: number[t], barycentric: bary)
    }
}

/// Two numbers in `0 ..< 1` folded into corner weights that cover a triangle
/// evenly. The square's two halves are pressed together across its diagonal
/// rather than pulled from one corner, which is what keeps an even input even
/// after the fold, and it costs no square root.
@inline(__always)
func ollinTriangleBarycentric(_ u: Double, _ v: Double) -> Vector3 {
    var x = u * 0.5, y = v * 0.5
    let offset = y - x
    if offset > 0 { y += offset } else { x -= offset }
    return Vector3(x, y, 1 - x - y)
}

// MARK: - Thinning to even spacing

/// Thin `samples` down to `count` by dropping the most crowded one over and
/// over: each sample carries the weight of how closely its neighbors press on
/// it, the heaviest goes, and the ones around it grow lighter for its absence.
///
/// The wanted spacing is never stated. It falls out of the count and the area,
/// which is what lets this work on a surface, where a radius has no obvious
/// value, as readily as it works on a flat rectangle.
private func thinToBlueNoise(_ samples: [SurfaceSample], count: Int,
                             area: Double) -> [SurfaceSample] {
    let m = samples.count
    guard count < m, count > 0, area > 0 else { return Array(samples.prefix(count)) }

    // The radius at which `count` disks would just cover the area in a
    // honeycomb, which is as tight as circles ever pack.
    let rMax = (area / (2 * 3.0.squareRoot() * Double(count))).squareRoot()
    let dMax = 2 * rMax
    guard dMax > 0, dMax.isFinite else { return Array(samples.prefix(count)) }

    // Pairs closer than this all count as equally crowded. Without the floor, a
    // pair that landed almost on top of each other outweighs everything else and
    // the pass spends its whole budget separating them.
    let dMin = dMax * 0.65 * (1 - pow(Double(count) / Double(m), 1.5))

    let positions = samples.map(\.position)
    let grid = PointGrid3(points: positions, cellSize: dMax)

    // Weight falls to nothing at `dMax` and rises steeply as a pair closes: the
    // eighth power is what makes the nearest neighbor, not the general crowd,
    // decide who goes.
    @inline(__always) func weight(_ d2: Double) -> Double {
        let d = Swift.min(Swift.max(d2.squareRoot(), dMin), dMax)
        let t = 1 - d / dMax
        let t2 = t * t, t4 = t2 * t2
        return t4 * t4
    }

    var weights = [Double](repeating: 0, count: m)
    var heap = SurfaceWeightHeap()
    heap.reserve(m * 2)
    for i in 0 ..< m {
        var w = 0.0
        grid.forNeighbors(of: positions[i], within: dMax) { j, d2 in
            if j != i { w += weight(d2) }
        }
        weights[i] = w
        heap.push(w, Int32(i))
    }

    var dropped = [Bool](repeating: false, count: m)
    var left = m
    while left > count, let top = heap.pop() {
        let i = Int(top.item)
        if dropped[i] { continue }
        // A stale entry: this sample grew lighter after the entry was made, so
        // put its true weight back and let the heap sort it out.
        if top.key != weights[i] { heap.push(weights[i], top.item); continue }
        dropped[i] = true
        left -= 1
        grid.forNeighbors(of: positions[i], within: dMax) { j, d2 in
            guard j != i, !dropped[j] else { return }
            weights[j] -= weight(d2)
            heap.push(weights[j], Int32(j))
        }
    }

    var out: [SurfaceSample] = []
    out.reserveCapacity(count)
    for i in 0 ..< m where !dropped[i] { out.append(samples[i]) }
    return out
}

/// A heaviest-first heap of sample weights. Entries are never edited in place:
/// a changed weight is pushed again and the old entry is recognized as stale
/// when it surfaces, which is cheaper than finding it. Equal weights break by
/// index, so a run repeats exactly.
private struct SurfaceWeightHeap {

    private var keys: [Double] = []
    private var items: [Int32] = []

    mutating func reserve(_ n: Int) {
        keys.reserveCapacity(n)
        items.reserveCapacity(n)
    }

    @inline(__always)
    private func heavier(_ a: Int, _ b: Int) -> Bool {
        keys[a] > keys[b] || (keys[a] == keys[b] && items[a] > items[b])
    }

    mutating func push(_ key: Double, _ item: Int32) {
        keys.append(key)
        items.append(item)
        var child = keys.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard heavier(child, parent) else { break }
            keys.swapAt(child, parent)
            items.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> (key: Double, item: Int32)? {
        guard let key = keys.first, let item = items.first else { return nil }
        let last = keys.count - 1
        keys[0] = keys[last]; items[0] = items[last]
        keys.removeLast(); items.removeLast()
        var parent = 0
        while true {
            let l = parent * 2 + 1, r = l + 1
            var top = parent
            if l < keys.count, heavier(l, top) { top = l }
            if r < keys.count, heavier(r, top) { top = r }
            if top == parent { break }
            keys.swapAt(parent, top)
            items.swapAt(parent, top)
            parent = top
        }
        return (key, item)
    }
}

// MARK: - Standing something up

public extension SurfaceSample {

    /// The turn that stands a mesh up along this sample's normal: the angles a
    /// `MeshInstance` takes, which point the mesh's own +y at the surface
    /// direction here. `spin` turns the mesh about that direction afterward, so
    /// a scattered field does not read as a field of clones.
    ///
    /// ```swift
    /// let trees = surfacePoints(on: island, count: 300)
    /// drawMesh(tree, instances: trees.map {
    ///     MeshInstance(position: $0.position,
    ///                  rotation: $0.alignment(spin: random(.tau)),
    ///                  scale: 0.4)
    /// })
    /// ```
    ///
    /// - Parameter spin: A turn about the normal, in radians.
    /// - Returns: Angles about the x, y, and z axes, in the order a
    ///   `MeshInstance` and `rotateX`/`rotateY`/`rotateZ` apply them.
    func alignment(spin: Double = 0) -> Vector3 {
        let n = normal.lengthSquared > 1e-18 ? normal.normalized : Vector3.unitY
        // With no turn about x, the pair (y, z) already reaches every direction:
        // z tilts +y away from upright by the angle to the normal, and y swings
        // that tilt around to the right side.
        let tilt = acos(Swift.min(Swift.max(n.y, -1), 1))
        let flat = (1 - n.y * n.y).squareRoot()
        let swing = flat > 1e-9 ? atan2(n.z, -n.x) : 0
        guard spin != 0 else { return Vector3(0, swing, tilt) }

        // A spin about the mesh's own up, applied before the two turns above,
        // comes out as a spin about the normal. Read the product back as the
        // three angles the placement takes.
        let m = ollinRotationY(swing) * ollinRotationZ(tilt) * ollinRotationY(spin)
        let y = asin(Swift.min(Swift.max(m.m02, -1), 1))
        if abs(m.m02) > 1 - 1e-9 {   // upright or upside down: x and z fold together
            return Vector3(0, y, atan2(m.m10, m.m11))
        }
        return Vector3(atan2(-m.m12, m.m22), y, atan2(-m.m01, m.m00))
    }
}

/// A 3x3 rotation, just enough to compose three turns and read the result back.
private struct Mat3 {
    var m00 = 1.0, m01 = 0.0, m02 = 0.0
    var m10 = 0.0, m11 = 1.0, m12 = 0.0
    var m20 = 0.0, m21 = 0.0, m22 = 1.0

    static func * (a: Mat3, b: Mat3) -> Mat3 {
        Mat3(m00: a.m00 * b.m00 + a.m01 * b.m10 + a.m02 * b.m20,
             m01: a.m00 * b.m01 + a.m01 * b.m11 + a.m02 * b.m21,
             m02: a.m00 * b.m02 + a.m01 * b.m12 + a.m02 * b.m22,
             m10: a.m10 * b.m00 + a.m11 * b.m10 + a.m12 * b.m20,
             m11: a.m10 * b.m01 + a.m11 * b.m11 + a.m12 * b.m21,
             m12: a.m10 * b.m02 + a.m11 * b.m12 + a.m12 * b.m22,
             m20: a.m20 * b.m00 + a.m21 * b.m10 + a.m22 * b.m20,
             m21: a.m20 * b.m01 + a.m21 * b.m11 + a.m22 * b.m21,
             m22: a.m20 * b.m02 + a.m21 * b.m12 + a.m22 * b.m22)
    }
}

private func ollinRotationY(_ a: Double) -> Mat3 {
    let c = cos(a), s = sin(a)
    return Mat3(m00: c, m01: 0, m02: s, m10: 0, m11: 1, m12: 0, m20: -s, m21: 0, m22: c)
}

private func ollinRotationZ(_ a: Double) -> Mat3 {
    let c = cos(a), s = sin(a)
    return Mat3(m00: c, m01: -s, m02: 0, m10: s, m11: c, m12: 0, m20: 0, m21: 0, m22: 1)
}

// MARK: - Sketch sugar

public extension Sketch {

    /// `count` points scattered evenly over `mesh`, by area rather than by
    /// vertex. Driven by the seeded `random`, so `seed(_:)` makes the layout
    /// repeat.
    ///
    /// ```swift
    /// seed(3)
    /// let spots = surfacePoints(on: rock, count: 250)
    /// drawMesh(moss, instances: spots.map {
    ///     MeshInstance(position: $0.position, rotation: $0.alignment(), scale: 0.1)
    /// })
    /// ```
    func surfacePoints(on mesh: Mesh, count: Int,
                       scatter: SurfaceScatter = .blueNoise) -> [SurfaceSample] {
        Ollin.surfacePoints(on: mesh, count: count, scatter: scatter, using: &rng)
    }

    /// Points scattered over `mesh` about `spacing` apart, the count following
    /// from the surface area. Driven by the seeded `random`.
    func surfacePoints(on mesh: Mesh, spacing: Double,
                       scatter: SurfaceScatter = .blueNoise) -> [SurfaceSample] {
        Ollin.surfacePoints(on: mesh, spacing: spacing, scatter: scatter, using: &rng)
    }
}
