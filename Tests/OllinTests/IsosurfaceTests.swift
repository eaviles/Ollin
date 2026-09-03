import Foundation
@testable import Ollin
import Testing

/// Pure-CPU checks on `isosurface(at:in:resolution:field:)` and `Metaballs`.
/// The load-bearing ones are the two a picture cannot show: that the mesh is
/// watertight (every edge shared by exactly two triangles, including across
/// the ambiguous faces where a naive tessellation cracks) and that it winds
/// outward. No GPU.
@Suite
struct IsosurfaceTests {

    // MARK: Support

    /// Every undirected edge of a triangle mesh, and how many triangles use it.
    private func edgeUse(_ mesh: Mesh) -> [Int: Int] {
        var counts: [Int: Int] = [:]
        let n = mesh.positions.count
        for t in stride(from: 0, to: mesh.indices.count, by: 3) {
            let tri = [Int(mesh.indices[t]), Int(mesh.indices[t + 1]), Int(mesh.indices[t + 2])]
            for e in 0 ..< 3 {
                let a = tri[e], b = tri[(e + 1) % 3]
                let key = min(a, b) * n + max(a, b)
                counts[key, default: 0] += 1
            }
        }
        return counts
    }

    /// The volume the mesh encloses, by the divergence theorem. Positive means
    /// the triangles wind outward; the magnitude is the enclosed volume.
    private func signedVolume(_ mesh: Mesh) -> Double {
        var total = 0.0
        for t in stride(from: 0, to: mesh.indices.count, by: 3) {
            let a = mesh.positions[Int(mesh.indices[t])]
            let b = mesh.positions[Int(mesh.indices[t + 1])]
            let c = mesh.positions[Int(mesh.indices[t + 2])]
            total += a.dot(b.cross(c))
        }
        return total / 6
    }

    /// How many separate pieces the mesh is in, by walking shared vertices.
    private func componentCount(_ mesh: Mesh) -> Int {
        var parent = Array(0 ..< mesh.positions.count)
        func find(_ x: Int) -> Int {
            var r = x
            while parent[r] != r { parent[r] = parent[parent[r]]; r = parent[r] }
            return r
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }
        var used = Set<Int>()
        for t in stride(from: 0, to: mesh.indices.count, by: 3) {
            let tri = [Int(mesh.indices[t]), Int(mesh.indices[t + 1]), Int(mesh.indices[t + 2])]
            used.formUnion(tri)
            union(tri[0], tri[1]); union(tri[1], tri[2])
        }
        return Set(used.map { find($0) }).count
    }

    /// A deterministic lumpy field: hashed value noise on a unit lattice,
    /// pulled hard negative away from the origin so the surface always closes
    /// inside the box. Full of saddles, which is the point.
    private func lumpyField(_ p: Vector3, cells: Double = 3.2, radius: Double = 1) -> Double {
        func hash(_ i: Int, _ j: Int, _ k: Int) -> Double {
            var h = UInt64(bitPattern: Int64(i &* 73_856_093 ^ j &* 19_349_663 ^ k &* 83_492_791))
            h ^= h >> 33; h = h &* 0xff51_afd7_ed55_8ccd
            h ^= h >> 33; h = h &* 0xc4ce_b9fe_1a85_ec53
            h ^= h >> 33
            return Double(h % 10_000) / 10_000 * 2 - 1
        }
        let q = p * (cells / radius)
        let fi = q.x.rounded(.down), fj = q.y.rounded(.down), fk = q.z.rounded(.down)
        let tx = q.x - fi, ty = q.y - fj, tz = q.z - fk
        func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }
        let sx = smooth(tx), sy = smooth(ty), sz = smooth(tz)
        var value = 0.0
        for dk in 0 ... 1 {
            for dj in 0 ... 1 {
                for di in 0 ... 1 {
                    let w = (di == 0 ? 1 - sx : sx) * (dj == 0 ? 1 - sy : sy) * (dk == 0 ? 1 - sz : sz)
                    value += w * hash(Int(fi) + di, Int(fj) + dj, Int(fk) + dk)
                }
            }
        }
        let r = p.length / radius
        return value - 3 * r * r * r * r
    }

    private let box = Box3(min: Vector3(-1.6, -1.6, -1.6), max: Vector3(1.6, 1.6, 1.6))

    // MARK: A sphere, the case with a known answer

    /// A linear radial field meshes to a sphere of the right size, with every
    /// vertex on it and every normal pointing straight out.
    @Test func radialFieldMeshesToASphere() {
        let radius = 1.0
        let mesh = isosurface(at: 0, in: box, resolution: 48) { radius - $0.length }

        #expect(!mesh.isEmpty)
        #expect(mesh.positions.count == mesh.normals.count)
        for (p, n) in zip(mesh.positions, mesh.normals) {
            #expect(abs(p.length - radius) < 0.01 * radius)
            #expect(n.dot(p.normalized) > 0.99)
        }
    }

    /// The enclosed volume matches the sphere's, which also pins the winding:
    /// a mesh wound inward would report the same volume negated.
    @Test func sphereVolumeIsRightAndTheWindingIsOutward() {
        let radius = 1.0
        let mesh = isosurface(at: 0, in: box, resolution: 48) { radius - $0.length }
        let expected = 4.0 / 3 * .pi * radius * radius * radius
        let volume = signedVolume(mesh)
        #expect(volume > 0)
        #expect(abs(volume - expected) < 0.02 * expected)
    }

    /// Each triangle's own facing agrees with the field gradient its vertices
    /// carry, everywhere. This is the per-triangle form of the volume check.
    @Test func everyTriangleFacesTheWayItsNormalsDo() {
        let mesh = isosurface(at: 0, in: box, resolution: 32) { 1 - $0.length }
        var checked = 0
        for t in stride(from: 0, to: mesh.indices.count, by: 3) {
            let ia = Int(mesh.indices[t]), ib = Int(mesh.indices[t + 1]), ic = Int(mesh.indices[t + 2])
            let a = mesh.positions[ia], b = mesh.positions[ib], c = mesh.positions[ic]
            let face = (b - a).cross(c - a)
            guard face.lengthSquared > 1e-18 else { continue }
            let vertexNormal = mesh.normals[ia] + mesh.normals[ib] + mesh.normals[ic]
            #expect(face.normalized.dot(vertexNormal.normalized) > 0)
            checked += 1
        }
        #expect(checked > 1000)
    }

    // MARK: Watertightness, the crack test

    /// A closed surface uses every edge exactly twice. One use means a crack.
    @Test func aClosedSurfaceHasNoCracks() {
        let mesh = isosurface(at: 0, in: box, resolution: 37) { 1 - $0.length }
        let counts = edgeUse(mesh)
        #expect(!counts.isEmpty)
        #expect(counts.values.allSatisfy { $0 == 2 })
    }

    /// The same, over a field dense with saddles. These are the configurations
    /// where two neighboring cells can disagree about how to join a shared
    /// face; the asymptotic decider reads only that face's four values, so
    /// they cannot. An odd resolution keeps the lattice off the field's own.
    @Test func aSaddleRichFieldHasNoCracks() {
        for resolution in [23, 34, 41] {
            let mesh = isosurface(at: 0, in: box, resolution: resolution) { lumpyField($0) }
            #expect(!mesh.isEmpty)
            let counts = edgeUse(mesh)
            let cracked = counts.values.filter { $0 != 2 }.count
            #expect(cracked == 0, "resolution \(resolution) left \(cracked) unpaired edges")
            #expect(signedVolume(mesh) > 0)
        }
    }

    /// Sitting the surface exactly on lattice values is the degenerate case
    /// that pushes crossings onto the cell corners. It must still close.
    @Test func aSurfaceThroughLatticeValuesStillCloses() {
        // The field takes whole-number values on a grid aligned with the march.
        let mesh = isosurface(at: 0, in: Box3(min: Vector3(-2, -2, -2), max: Vector3(2, 2, 2)),
                              resolution: 8) { p in
            2 - max(abs(p.x), max(abs(p.y), abs(p.z)))
        }
        #expect(!mesh.isEmpty)
        #expect(edgeUse(mesh).values.allSatisfy { $0 == 2 })
    }

    // MARK: Conventions and edges of the API

    /// Inside is where the field runs above the level, so raising the level
    /// shrinks the surface.
    @Test func raisingTheLevelShrinksTheSurface() {
        let low = isosurface(at: 0.2, in: box, resolution: 32) { 1 - $0.length }
        let high = isosurface(at: 0.6, in: box, resolution: 32) { 1 - $0.length }
        #expect(signedVolume(low) > signedVolume(high))
        // The surfaces sit at radius 0.8 and 0.4.
        for p in low.positions { #expect(abs(p.length - 0.8) < 0.02) }
        for p in high.positions { #expect(abs(p.length - 0.4) < 0.02) }
    }

    /// A field that never crosses the level has no surface, from either side.
    @Test func aFieldThatNeverCrossesHasNoSurface() {
        #expect(isosurface(at: 0, in: box, resolution: 16) { _ in -1 }.isEmpty)
        #expect(isosurface(at: 0, in: box, resolution: 16) { _ in 1 }.isEmpty)
    }

    /// A degenerate box yields nothing rather than trapping.
    @Test func aDegenerateBoxYieldsNothing() {
        let flat = Box3(min: Vector3(1, 2, 3), max: Vector3(1, 2, 3))
        #expect(isosurface(at: 0, in: flat, resolution: 16) { 1 - $0.length }.isEmpty)
        #expect(isosurface(at: 0, in: box, resolution: 0) { 1 - $0.length }.isEmpty)
    }

    /// The march is a pure function of the field, so two runs agree exactly.
    @Test func theMarchIsDeterministic() {
        func build() -> Mesh { isosurface(at: 0, in: box, resolution: 29) { lumpyField($0) } }
        let a = build(), b = build()
        #expect(a.indices == b.indices)
        #expect(a.positions.count == b.positions.count)
        for (p, q) in zip(a.positions, b.positions) { #expect(p == q) }
    }

    /// Cells stay cubic, so a long thin box gets proportionally fewer of them
    /// across its short sides rather than stretched ones.
    @Test func cellsStayCubicInALongBox() {
        let long = Box3(min: Vector3(-4, -1, -1), max: Vector3(4, 1, 1))
        let mesh = isosurface(at: 0, in: long, resolution: 64) { p in
            0.6 - Vector3(p.x - clamp(p.x, -3, 3), p.y, p.z).length
        }
        #expect(!mesh.isEmpty)
        #expect(edgeUse(mesh).values.allSatisfy { $0 == 2 })
        // A capsule of radius 0.6 with a 6-long core.
        let expected = Double.pi * 0.36 * 6 + 4.0 / 3 * Double.pi * 0.216
        #expect(abs(signedVolume(mesh) - expected) < 0.04 * expected)
    }

    // MARK: Metaballs

    /// The soft-object falloff runs 1 at the center to 0 at the reach, and is
    /// exactly a half at the quarter point. That last value is what makes a
    /// lone ball read at its own radius.
    @Test func theFalloffHitsItsThreeKnownValues() {
        #expect(Metaballs.falloff(0) == 1)
        #expect(abs(Metaballs.falloff(1)) < 1e-12)
        #expect(abs(Metaballs.falloff(0.25) - 0.5) < 1e-12)
    }

    /// A single ball meshes to a sphere of exactly the radius asked for.
    @Test func aLoneBallReadsAtItsOwnRadius() {
        var field = Metaballs()
        field.add(at: Vector3(0, 0, 0), radius: 50)
        let mesh = field.mesh(resolution: 48)
        #expect(!mesh.isEmpty)
        for p in mesh.positions { #expect(abs(p.length - 50) < 0.5) }
        #expect(edgeUse(mesh).values.allSatisfy { $0 == 2 })
    }

    /// Balls out of each other's reach stay separate pieces; brought together
    /// they fuse into one.
    @Test func ballsMergeWhenTheyComeWithinReach() {
        func pieces(gap: Double) -> Int {
            var field = Metaballs()
            field.add(at: Vector3(-gap / 2, 0, 0), radius: 30)
            field.add(at: Vector3(gap / 2, 0, 0), radius: 30)
            return componentCount(field.mesh(resolution: 56))
        }
        #expect(pieces(gap: 200) == 2)
        #expect(pieces(gap: 70) == 1)
    }

    /// The field is the sum, so two balls lift the value between them above
    /// what either reaches there alone. That lift is the merge.
    @Test func twoBallsLiftTheFieldBetweenThem() {
        var one = Metaballs(); one.add(at: Vector3(-40, 0, 0), radius: 30)
        var two = one; two.add(at: Vector3(40, 0, 0), radius: 30)
        let middle = Vector3.zero
        #expect(two.value(at: middle) > one.value(at: middle))
        #expect(two.value(at: middle) == 2 * one.value(at: middle))
    }

    /// A negative ball carves rather than joins.
    @Test func aNegativeBallCarvesIntoItsNeighbour() {
        var field = Metaballs()
        field.add(at: .zero, radius: 60)
        let solid = field.value(at: Vector3(30, 0, 0))
        field.add(at: Vector3(40, 0, 0), radius: 40, strength: -1)
        #expect(field.value(at: Vector3(30, 0, 0)) < solid)
    }

    /// An empty field has no bounds and no mesh.
    @Test func anEmptyFieldMeshesToNothing() {
        let field = Metaballs()
        #expect(field.bounds == nil)
        #expect(field.mesh().isEmpty)
        #expect(field.value(at: .zero) == 0)
    }

    /// The bounds cover every ball's whole reach, which is what lets the mesh
    /// close instead of being clipped.
    @Test func boundsCoverEveryBallsReach() {
        var field = Metaballs()
        field.add(at: Vector3(100, 0, 0), radius: 25)   // reach 50, so x over 50 ... 150
        field.add(at: Vector3(-10, 60, 0), radius: 10)  // reach 20, so x over -30 ... 10
        guard let b = field.bounds else { Issue.record("no bounds"); return }
        #expect(b.min.x == -30 && b.max.x == 150)
        #expect(b.min.y == -50 && b.max.y == 80)
    }
}
