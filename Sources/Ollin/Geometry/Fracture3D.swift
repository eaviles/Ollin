import Foundation

/// Breaking a solid into pieces: the mesh's volume is cut into convex cells
/// that fit back together exactly, the way a dropped cup leaves every shard on
/// the floor.
///
/// The cut is the 3D Voronoi diagram of a handful of seed points inside the
/// solid, so every piece is convex and the pieces tile the whole volume with no
/// gap and no overlap. `fractured(into:seed:)` spreads the seeds evenly, which
/// reads as something that came apart on its own.
/// `fractured(into:around:seed:)` crowds them at a point, which reads as
/// something struck there: small chips at the blow, long wedges away from it.
///
/// ```swift
/// for piece in Mesh.box(size: 1).fractured(into: 12, seed: 3) {
///     withState {
///         translate(piece.centroid)
///         drawMesh(piece.mapPositions { $0 - piece.centroid })
///     }
/// }
/// ```
///
/// Because the pieces are convex, each one is ready to be a rigid body: hand
/// the solver the piece's points as a hull and put the body at the piece's
/// `centroid`. A solid that is *not* convex breaks as its convex hull, which is
/// the honest limit of a Voronoi cut. A cup breaks into the shards of the solid
/// cup, not of the hollow one.
public extension Mesh {
    /// Break the solid into `pieces` convex cells, spread evenly.
    ///
    /// The same `seed` always gives the same break. The pieces' volumes sum to
    /// the solid's own, and each piece keeps the source mesh's `material`.
    ///
    /// - Parameters:
    ///   - pieces: How many cells to cut, at least one.
    ///   - seed: The seed behind the cut. The same seed repeats a break.
    func fractured(into pieces: Int, seed: Int = 0) -> [Mesh] {
        fractured(into: pieces, around: nil, seed: seed)
    }

    /// Break the solid into `pieces` convex cells crowded around `impact`.
    ///
    /// The seeds are drawn thickest at `impact` and thin out with distance, so
    /// the break reads as a blow landing there. The point can sit outside the
    /// solid, which breaks it as if struck a glancing blow off one side.
    ///
    /// - Parameters:
    ///   - pieces: How many cells to cut, at least one.
    ///   - impact: Where the break starts, in the mesh's own coordinates.
    ///   - seed: The seed behind the cut. The same seed repeats a break.
    func fractured(into pieces: Int, around impact: Vector3, seed: Int = 0) -> [Mesh] {
        fractured(into: pieces, around: .some(impact), seed: seed)
    }

    private func fractured(into pieces: Int, around impact: Vector3?, seed: Int) -> [Mesh] {
        guard !isEmpty else { return [] }
        guard pieces > 1 else { return [self] }
        let solid = ConvexSolid(hullOf: positions)
        guard !solid.planes.isEmpty else { return [self] }

        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(seed)))
        let sites = solid.seeds(count: pieces, impact: impact, rng: &rng)
        guard sites.count > 1 else { return [self] }

        // The hull is cut out of the starting box once; each cell is that solid
        // with the seeds' half-spaces taken off it.
        var whole = solid.blank
        for (normal, offset) in solid.planes {
            whole.clip(normal: normal, offset: offset, epsilon: solid.epsilon)
        }
        guard !whole.isEmpty else { return [self] }

        let smallest = solid.volume * 1e-6
        var broken: [Mesh] = []
        broken.reserveCapacity(sites.count)
        for (i, site) in sites.enumerated() {
            var cell = whole
            for (j, other) in sites.enumerated() where j != i && !cell.isEmpty {
                // Everything closer to this seed than to that one: the squared
                // terms cancel, leaving one half-space per pair of seeds.
                let normal = (other - site) * 2
                let offset = other.lengthSquared - site.lengthSquared
                guard normal.lengthSquared > 1e-24 else { continue }
                cell.clip(normal: normal, offset: offset, epsilon: solid.epsilon)
            }
            guard !cell.isEmpty, cell.volume > smallest else { continue }
            broken.append(cell.mesh(material: material))
        }
        return broken.isEmpty ? [self] : broken
    }

    /// How much space the solid encloses.
    ///
    /// Worked out from the triangles themselves, so it holds for any closed
    /// mesh however it was built. A mesh with holes in its surface encloses
    /// nothing definite, and the number it gives back means nothing.
    var volume: Double {
        abs(Mesh.signedVolumeAndMoment(positions: positions, indices: indices).0)
    }

    /// The balance point of the solid: where it would sit on a pin.
    ///
    /// This is the volume's center, not the average of the vertices, so a
    /// densely tessellated end does not drag it. A mesh enclosing no volume
    /// falls back to the average of its points.
    var centroid: Vector3 {
        let (volume, moment) = Mesh.signedVolumeAndMoment(positions: positions, indices: indices)
        guard abs(volume) > 1e-12 else {
            guard !positions.isEmpty else { return .zero }
            return positions.reduce(.zero, +) / Double(positions.count)
        }
        return moment / volume
    }

    /// A copy with every position passed through `transform`, normals and all
    /// else untouched: the way to move a piece onto its own origin.
    func mapPositions(_ transform: (Vector3) -> Vector3) -> Mesh {
        var copy = self
        copy.positions = positions.map(transform)
        return copy
    }

    /// The signed volume and the volume-weighted moment, both from the same
    /// walk over the triangles (each one closing a tetrahedron on the origin).
    internal static func signedVolumeAndMoment(positions: [Vector3], indices: [UInt32]) -> (Double, Vector3) {
        var volume = 0.0
        var moment = Vector3.zero
        var i = 0
        while i + 2 < indices.count {
            let a = positions[Int(indices[i])]
            let b = positions[Int(indices[i + 1])]
            let c = positions[Int(indices[i + 2])]
            let piece = a.dot(b.cross(c)) / 6
            volume += piece
            moment += (a + b + c) * (piece / 4)
            i += 3
        }
        return (volume, moment)
    }
}

/// The convex solid a mesh breaks inside: its hull, kept as the planes that
/// bound it plus a box big enough to start every cell from.
struct ConvexSolid {
    /// One outward plane per hull face, as `normal · p <= offset`.
    let planes: [(Vector3, Double)]
    let box: Box3
    let epsilon: Double
    let volume: Double

    init(hullOf points: [Vector3]) {
        let faces = convexHullFaces(of: points)
        let bounds = Box3(containing: points) ?? .zero
        box = bounds
        let tolerance = Swift.max(bounds.longestSide, 1e-12) * 1e-9
        epsilon = tolerance
        var sides: [(Vector3, Double)] = []
        var volume = 0.0
        for face in faces {
            let cross = (face.1 - face.0).cross(face.2 - face.0)
            volume += face.0.dot(face.1.cross(face.2)) / 6
            guard cross.lengthSquared > tolerance * tolerance else { continue }
            let normal = cross.normalized
            let offset = normal.dot(face.0)
            // Coplanar faces (the two triangles of a box's side) are one plane.
            let known = sides.contains { $0.0.dot(normal) > 0.999_99 && abs($0.1 - offset) <= tolerance }
            if !known { sides.append((normal, offset)) }
        }
        planes = sides
        self.volume = abs(volume)
    }

    /// A cell before any cutting: a box comfortably outside the solid, so the
    /// hull's own planes are what give the outside pieces their skin.
    var blank: ConvexCell {
        ConvexCell(box: Box3(center: box.center, size: box.size * 2 + Vector3(1, 1, 1) * 1e-6))
    }

    /// Whether a point is inside the hull.
    func contains(_ point: Vector3) -> Bool {
        planes.allSatisfy { $0.0.dot(point) <= $0.1 + epsilon }
    }

    /// Seeds inside the solid: evenly spread, or crowded at a point.
    func seeds(count: Int, impact: Vector3?, rng: inout SplitMix64) -> [Vector3] {
        var sites: [Vector3] = []
        sites.reserveCapacity(count)
        if let impact, contains(impact) { sites.append(impact) }
        let center = impact ?? box.center
        let reach = Swift.max((box.max - center).length, (box.min - center).length)

        while sites.count < count {
            var best: Vector3?
            var bestScore = -Double.infinity
            // Mitchell's best-candidate: a few tries, keep the one standing
            // farthest from the seeds already placed.
            for _ in 0 ..< 8 {
                guard let candidate = seed(impact: impact, reach: reach, rng: &rng) else { continue }
                let score = sites.map { ($0 - candidate).lengthSquared }.min() ?? .infinity
                if score > bestScore { bestScore = score; best = candidate }
            }
            guard let best else { break }
            sites.append(best)
        }
        return sites
    }

    private func seed(impact: Vector3?, reach: Double, rng: inout SplitMix64) -> Vector3? {
        for _ in 0 ..< 64 {
            let point: Vector3
            if let impact {
                // Radius as a power of a uniform draw, so the chips at the blow
                // are small and the wedges away from it are long.
                let u = Double.random(in: 0 ..< 1, using: &rng)
                let radius = reach * pow(u, 1.9)
                let z = Double.random(in: -1 ..< 1, using: &rng)
                let angle = Double.random(in: 0 ..< 2 * .pi, using: &rng)
                let r = (1 - z * z).squareRoot()
                point = impact + Vector3(r * cos(angle), r * sin(angle), z) * radius
            } else {
                point = Vector3(Double.random(in: box.min.x ..< box.max.x, using: &rng),
                                Double.random(in: box.min.y ..< box.max.y, using: &rng),
                                Double.random(in: box.min.z ..< box.max.z, using: &rng))
            }
            if contains(point) { return point }
        }
        return nil
    }
}

/// A convex solid held as its faces, each a loop of points wound counterclockwise
/// seen from outside. Cutting one by a plane is the whole of the 3D fracture:
/// every face is trimmed, and the ring of new edges is capped with one new face.
struct ConvexCell {
    var faces: [[Vector3]]

    init(box: Box3) {
        let lo = box.min, hi = box.max
        let corners = [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z),
                       Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z),
                       Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z),
                       Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
        let sides = [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4],
                     [2, 3, 7, 6], [1, 2, 6, 5], [0, 3, 7, 4]]
        let center = box.center
        faces = sides.map { side in
            let loop = side.map { corners[$0] }
            // Turn each side outward by the one test that cannot be got wrong:
            // its normal must point away from the middle of the box.
            let normal = (loop[1] - loop[0]).cross(loop[2] - loop[0])
            return normal.dot(loop[0] - center) >= 0 ? loop : loop.reversed()
        }
    }

    /// A solid needs four faces; fewer means the cuts took everything.
    var isEmpty: Bool { faces.count < 4 }

    /// Cut away everything past a plane, keeping `normal · p <= offset`.
    mutating func clip(normal: Vector3, offset: Double, epsilon: Double) {
        let scale = Swift.max(normal.length, 1e-12)
        let tolerance = epsilon * scale
        var kept: [[Vector3]] = []
        var rim: [Vector3] = []
        var removedAny = false
        for face in faces {
            var trimmed: [Vector3] = []
            trimmed.reserveCapacity(face.count + 1)
            for i in face.indices {
                let a = face[i], b = face[(i + 1) % face.count]
                let da = normal.dot(a) - offset, db = normal.dot(b) - offset
                if da > tolerance { removedAny = true }
                if da <= tolerance {
                    trimmed.append(a)
                    // A corner already sitting on the plane is part of the new
                    // face's rim. Leaving it out is what tears a hole where
                    // several planes meet at one corner.
                    if da >= -tolerance { rim.append(a) }
                }
                if (da < -tolerance && db > tolerance) || (da > tolerance && db < -tolerance) {
                    let crossing = a + (b - a) * (da / (da - db))
                    trimmed.append(crossing)
                    rim.append(crossing)
                }
            }
            if trimmed.count >= 3 { kept.append(trimmed) }
        }
        // The plane missed: nothing to trim and no new face to cap it with.
        guard removedAny else { return }
        faces = kept
        guard !faces.isEmpty else { return }
        // The same corner reached along two faces lands twice, a hair apart:
        // weld generously enough to merge those and not two real corners.
        let ring = ConvexCell.welded(rim, tolerance: Swift.max(tolerance * 1000, 1e-12))
        guard ring.count >= 3 else { return }
        faces.append(ConvexCell.loop(of: ring, around: normal.normalized))
    }

    /// The volume the faces enclose.
    var volume: Double {
        var total = 0.0
        for face in faces where face.count >= 3 {
            for i in 1 ..< face.count - 1 {
                total += face[0].dot(face[i].cross(face[i + 1])) / 6
            }
        }
        return abs(total)
    }

    /// The cell as a flat-shaded mesh, one normal per face.
    func mesh(material: MeshMaterial?) -> Mesh {
        var positions: [Vector3] = []
        var normals: [Vector3] = []
        var indices: [UInt32] = []
        for face in faces where face.count >= 3 {
            let normal = (face[1] - face[0]).cross(face[2] - face[0]).normalized
            let base = UInt32(positions.count)
            positions.append(contentsOf: face)
            normals.append(contentsOf: Array(repeating: normal, count: face.count))
            for i in 1 ..< face.count - 1 {
                indices.append(contentsOf: [base, base + UInt32(i), base + UInt32(i + 1)])
            }
        }
        return Mesh(positions: positions, normals: normals, indices: indices, material: material)
    }

    /// The same point reached from two faces arrives twice; keep one of each.
    private static func welded(_ points: [Vector3], tolerance: Double) -> [Vector3] {
        var unique: [Vector3] = []
        for point in points where !unique.contains(where: { $0.distanceSquared(to: point) <= tolerance * tolerance }) {
            unique.append(point)
        }
        return unique
    }

    /// The cut's new face: its points sorted around the plane's normal, which
    /// is a loop because the solid being cut is convex.
    private static func loop(of points: [Vector3], around normal: Vector3) -> [Vector3] {
        let center = points.reduce(.zero, +) / Double(points.count)
        let helper = abs(normal.x) < 0.9 ? Vector3.unitX : Vector3.unitY
        let u = normal.cross(helper).normalized
        let v = normal.cross(u)
        return points.sorted {
            let a = $0 - center, b = $1 - center
            return atan2(v.dot(a), u.dot(a)) < atan2(v.dot(b), u.dot(b))
        }
    }
}
