import Foundation
import simd
import Testing
@testable import Ollin

/// Pure-CPU checks on scattering points over a mesh surface. The laws they lean
/// on are all statements about area, because area is the whole point of the
/// feature: a triangle receives points in proportion to how much skin it owns,
/// never to how many vertices it cost, and inside one triangle no corner is
/// favored over another. The even-spacing pass is held to the distance a
/// honeycomb of that many points would keep, and the standing-up angles are held
/// to the matrix the renderer actually builds from them. No GPU.
@Suite
struct SurfaceSamplingTests {

    // MARK: - Meshes picked to be awkward

    /// A unit square in the xz plane, facing +y, as two triangles.
    static func square() -> Mesh {
        Mesh(positions: [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)],
             normals: [.unitY, .unitY, .unitY, .unitY],
             indices: [0, 1, 2, 0, 2, 3],
             uvs: [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
    }

    /// One triangle with corners far enough apart to measure inside.
    static func triangle() -> Mesh {
        Mesh(positions: [Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(0, 0, 4)],
             indices: [0, 1, 2])
    }

    /// The mesh that states the whole case: a 4x1 slab of skin whose left
    /// quarter is cut into 64 tiny triangles and whose right three quarters are
    /// two large ones. Sampling the vertex list would put nearly every point in
    /// the left quarter; sampling the surface must put a quarter of them there.
    static func lopsided() -> Mesh {
        var positions: [Vector3] = []
        var indices: [UInt32] = []
        // Left quarter: x in 0...1, cut 8 x 4.
        for row in 0 ... 4 {
            for col in 0 ... 8 {
                positions.append(Vector3(Double(col) / 8, 0, Double(row) / 4))
            }
        }
        for row in 0 ..< 4 {
            for col in 0 ..< 8 {
                let a = UInt32(row * 9 + col), b = a + 1, c = a + 9, d = c + 1
                indices.append(contentsOf: [a, b, d, a, d, c])
            }
        }
        // Right three quarters: x in 1...4, two triangles.
        let base = UInt32(positions.count)
        positions.append(contentsOf: [Vector3(1, 0, 0), Vector3(4, 0, 0),
                                      Vector3(4, 0, 1), Vector3(1, 0, 1)])
        indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
        return Mesh(positions: positions, indices: indices)
    }

    /// A square with a zero-area triangle wedged between its two real ones, to
    /// pin that a triangle with no skin is never picked and never shifts the
    /// numbering of the ones that follow it.
    static func squareWithACollapsedTriangle() -> Mesh {
        Mesh(positions: [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)],
             indices: [0, 1, 2, 0, 1, 1, 0, 2, 3])
    }

    // MARK: - The surface, not the vertices

    /// Area is what decides where points land. The lopsided slab owns a quarter
    /// of its skin on the left, where 88 of its 92 triangles and 45 of its 49
    /// vertices are, so a vertex-driven scatter would put 92% of the points
    /// there and a surface-driven one puts 25%.
    @Test func countsFollowAreaAndNotTheVertexList() {
        let mesh = Self.lopsided()
        #expect(mesh.triangleCount == 66)
        let leftVertexShare = Double(45) / Double(mesh.positions.count)
        #expect(leftVertexShare > 0.9)   // the trap a vertex scatter falls into

        var rng = SplitMix64(seed: 11)
        let n = 20_000
        let points = surfacePoints(on: mesh, count: n, scatter: .random, using: &rng)
        let left = points.filter { $0.position.x < 1 }.count
        let share = Double(left) / Double(n)
        // A quarter of the area, within four standard errors of the count.
        let sigma = (0.25 * 0.75 / Double(n)).squareRoot()
        #expect(abs(share - 0.25) < 4 * sigma)
    }

    /// The even-spacing pass thins the draw down without favoring big triangles
    /// or small ones, so the area law survives it.
    @Test func evenSpacingKeepsTheAreaShares() {
        var rng = SplitMix64(seed: 12)
        let n = 4_000
        let points = surfacePoints(on: Self.lopsided(), count: n, using: &rng)
        #expect(points.count == n)
        let share = Double(points.filter { $0.position.x < 1 }.count) / Double(n)
        #expect(abs(share - 0.25) < 0.02)
    }

    /// Inside one triangle no corner is favored: the chance a corner's weight
    /// stays under `t` is exactly `1 - (1 - t)^2`, because the region where it
    /// exceeds `t` is the same triangle shrunk by `1 - t`.
    @Test func theFoldFillsATriangleEvenly() {
        var rng = SplitMix64(seed: 13)
        let n = 40_000
        let points = surfacePoints(on: Self.triangle(), count: n, scatter: .random, using: &rng)
        let sigma = (1.0 / Double(n)).squareRoot()

        for t in [0.25, 0.5, 0.75] {
            let want = 1 - (1 - t) * (1 - t)
            for corner in 0 ..< 3 {
                let weight: (SurfaceSample) -> Double = {
                    corner == 0 ? $0.barycentric.x : (corner == 1 ? $0.barycentric.y : $0.barycentric.z)
                }
                let got = Double(points.filter { weight($0) < t }.count) / Double(n)
                #expect(abs(got - want) < 4 * sigma)
            }
        }

        // And the average of each weight is a third.
        let mean = points.reduce(Vector3.zero) { $0 + $1.barycentric } * (1 / Double(n))
        #expect(abs(mean.x - 1.0 / 3) < 0.01)
        #expect(abs(mean.y - 1.0 / 3) < 0.01)
        #expect(abs(mean.z - 1.0 / 3) < 0.01)
    }

    // MARK: - What a sample says about itself

    /// A sample's parts have to agree with each other: the weights add to one,
    /// none is negative, and blending the named triangle's corners by them
    /// reproduces the position. That is also what pins the triangle number to
    /// the mesh's own numbering.
    @Test func everySamplePlacesItselfInTheTriangleItNames() {
        let mesh = Mesh.sphere(radius: 1.4, segments: 24, rings: 12)
        var rng = SplitMix64(seed: 14)
        let points = surfacePoints(on: mesh, count: 600, scatter: .random, using: &rng)

        for s in points {
            #expect(s.barycentric.x >= 0 && s.barycentric.y >= 0 && s.barycentric.z >= 0)
            #expect(abs(s.barycentric.x + s.barycentric.y + s.barycentric.z - 1) < 1e-12)
            #expect(s.triangle >= 0 && s.triangle < mesh.triangleCount)

            let i = s.triangle * 3
            let a = mesh.positions[Int(mesh.indices[i])]
            let b = mesh.positions[Int(mesh.indices[i + 1])]
            let c = mesh.positions[Int(mesh.indices[i + 2])]
            let rebuilt = a * s.barycentric.x + b * s.barycentric.y + c * s.barycentric.z
            #expect((rebuilt - s.position).length < 1e-9)
        }
    }

    /// A triangle with no area is never picked, and it does not shift the
    /// numbers of the triangles after it.
    @Test func aCollapsedTriangleIsSkippedWithoutRenumbering() {
        let mesh = Self.squareWithACollapsedTriangle()
        var rng = SplitMix64(seed: 15)
        let points = surfacePoints(on: mesh, count: 500, scatter: .random, using: &rng)
        #expect(points.count == 500)
        #expect(!points.contains { $0.triangle == 1 })       // the collapsed one
        #expect(points.contains { $0.triangle == 0 })
        #expect(points.contains { $0.triangle == 2 })
        for s in points {
            let i = s.triangle * 3
            let a = mesh.positions[Int(mesh.indices[i])]
            let b = mesh.positions[Int(mesh.indices[i + 1])]
            let c = mesh.positions[Int(mesh.indices[i + 2])]
            let rebuilt = a * s.barycentric.x + b * s.barycentric.y + c * s.barycentric.z
            #expect((rebuilt - s.position).length < 1e-9)
        }
    }

    /// Normals are unit length, blended from the mesh's own when it has them,
    /// and taken from the triangle's winding when it has none.
    @Test func normalsComeFromTheSurface() {
        var rng = SplitMix64(seed: 16)

        let flat = Self.square()                      // carries +y normals
        for s in surfacePoints(on: flat, count: 200, scatter: .random, using: &rng) {
            #expect(abs(s.normal.length - 1) < 1e-12)
            #expect((s.normal - Vector3.unitY).length < 1e-12)
        }

        let bare = Self.triangle()                    // carries none: winding decides
        for s in surfacePoints(on: bare, count: 200, scatter: .random, using: &rng) {
            #expect((s.normal - Vector3(0, -1, 0)).length < 1e-9)
        }

        let ball = Mesh.sphere(radius: 2, segments: 32, rings: 16)
        for s in surfacePoints(on: ball, count: 300, scatter: .random, using: &rng) {
            #expect(abs(s.normal.length - 1) < 1e-9)
            // A sphere's normal points away from its middle.
            #expect(s.normal.dot(s.position.normalized) > 0.99)
        }
    }

    /// The texture coordinate is blended the same way the position is, so on a
    /// square mapped corner to corner it reads the position back.
    @Test func textureCoordinatesFollowThePosition() {
        var rng = SplitMix64(seed: 17)
        for s in surfacePoints(on: Self.square(), count: 300, scatter: .random, using: &rng) {
            #expect(abs(s.uv.x - s.position.x) < 1e-9)
            #expect(abs(s.uv.y - s.position.z) < 1e-9)
        }
        // A mesh with no coordinates reports zero rather than a stale value.
        var bare = SplitMix64(seed: 18)
        for s in surfacePoints(on: Self.triangle(), count: 50, scatter: .random, using: &bare) {
            #expect(s.uv == .zero)
        }
    }

    // MARK: - Even spacing

    /// The point of `.blueNoise`: neighbors keep their distance. The yardstick
    /// is the spacing a honeycomb of that many points would hold on that much
    /// skin, and a plain draw comes nowhere near it.
    @Test func evenSpacingKeepsNeighborsApart() {
        let mesh = Mesh.plane(width: 10, depth: 10)
        let n = 900
        let ideal = (2 * mesh.surfaceArea / (3.0.squareRoot() * Double(n))).squareRoot()

        var rng = SplitMix64(seed: 19)
        let even = surfacePoints(on: mesh, count: n, using: &rng)
        var other = SplitMix64(seed: 19)
        let plain = surfacePoints(on: mesh, count: n, scatter: .random, using: &other)

        #expect(even.count == n)
        #expect(plain.count == n)

        let evenGap = Self.nearestNeighborDistance(even)
        let plainGap = Self.nearestNeighborDistance(plain)
        #expect(evenGap.smallest > 0.65 * ideal)
        #expect(evenGap.smallest > 6 * plainGap.smallest)
        #expect(evenGap.mean > plainGap.mean)
        #expect(abs(evenGap.mean - ideal) < 0.25 * ideal)
    }

    /// Asking by spacing sets the count from the area, and the points then
    /// actually keep about that distance.
    @Test func spacingSetsTheCount() {
        let mesh = Mesh.plane(width: 8, depth: 8)
        let spacing = 0.4
        var rng = SplitMix64(seed: 20)
        let points = surfacePoints(on: mesh, spacing: spacing, using: &rng)

        let want = Int((mesh.surfaceArea * 2 / (3.0.squareRoot() * spacing * spacing)).rounded())
        #expect(points.count == want)
        #expect(abs(Self.nearestNeighborDistance(points).mean - spacing) < 0.25 * spacing)
    }

    /// The area a mesh reports is the sum of its triangles, and the primitives
    /// agree with the formulas for their shapes.
    @Test func surfaceAreaAddsUpTheTriangles() {
        #expect(abs(Self.square().surfaceArea - 1) < 1e-12)
        #expect(abs(Mesh.plane(width: 3, depth: 5).surfaceArea - 15) < 1e-9)
        #expect(abs(Mesh.box(size: 2).surfaceArea - 24) < 1e-9)
        // A fine sphere approaches 4 pi r^2 from below, its facets cutting corners.
        let ball = Mesh.sphere(radius: 1, segments: 128, rings: 64).surfaceArea
        #expect(ball < 4 * Double.pi && ball > 4 * Double.pi * 0.999)
        #expect(Mesh(positions: [], indices: []).surfaceArea == 0)
    }

    // MARK: - Standing something up

    /// `alignment` is held to the matrix the renderer builds from it: place a
    /// copy with those angles and the mesh's own up has to end pointing along
    /// the sample's normal, whatever direction that is and whatever spin is
    /// asked for.
    @Test func alignmentPointsTheMeshUpTheNormal() {
        var rng = SplitMix64(seed: 21)
        var normals: [Vector3] = [.unitY, -.unitY, .unitX, -.unitX, .unitZ, -.unitZ]
        for _ in 0 ..< 200 {
            let v = Vector3(Double.random(in: -1 ... 1, using: &rng),
                            Double.random(in: -1 ... 1, using: &rng),
                            Double.random(in: -1 ... 1, using: &rng))
            if v.lengthSquared > 1e-6 { normals.append(v.normalized) }
        }

        for n in normals {
            let sample = SurfaceSample(position: .zero, normal: n, uv: .zero,
                                       triangle: 0, barycentric: Vector3(1, 0, 0))
            for spin in [0.0, 0.7, -2.2, Double.pi] {
                let placement = MeshInstance(position: .zero,
                                             rotation: sample.alignment(spin: spin))
                let up = Self.turn(Vector3.unitY, by: placement)
                #expect((up - n).length < 1e-5)
            }
        }
    }

    /// The spin turns the copy about the normal and about nothing else: the up
    /// direction holds still while a sideways point sweeps the asked-for angle.
    @Test func spinTurnsAboutTheNormalOnly() {
        let n = Vector3(0.3, 0.8, -0.5).normalized
        let sample = SurfaceSample(position: .zero, normal: n, uv: .zero,
                                   triangle: 0, barycentric: Vector3(1, 0, 0))
        let rest = Self.turn(Vector3.unitX, by: MeshInstance(rotation: sample.alignment()))
        for spin in [0.4, 1.9, -1.1] {
            let turned = Self.turn(Vector3.unitX, by: MeshInstance(rotation: sample.alignment(spin: spin)))
            // Both lie the same distance off the normal, and the angle between
            // their sideways parts is the spin.
            #expect(abs(rest.dot(n) - turned.dot(n)) < 1e-6)
            let a = (rest - n * rest.dot(n)).normalized
            let b = (turned - n * turned.dot(n)).normalized
            let angle = atan2(a.cross(b).dot(n), a.dot(b))
            #expect(abs(atan2(sin(spin - angle), cos(spin - angle))) < 1e-6)
        }
    }

    // MARK: - Repeatability and the empty cases

    /// The same seed lays the same points down, and a different one does not.
    @Test func theSameSeedRepeatsTheScatter() {
        let mesh = Mesh.torus(radius: 1, tube: 0.3)
        var a = SplitMix64(seed: 5)
        var b = SplitMix64(seed: 5)
        var c = SplitMix64(seed: 6)
        let first = surfacePoints(on: mesh, count: 300, using: &a)
        let again = surfacePoints(on: mesh, count: 300, using: &b)
        let other = surfacePoints(on: mesh, count: 300, scatter: .blueNoise, using: &c)
        #expect(first == again)
        #expect(first != other)

        var d = SplitMix64(seed: 5)
        var e = SplitMix64(seed: 5)
        #expect(surfacePoints(on: mesh, count: 200, scatter: .random, using: &d)
                == surfacePoints(on: mesh, count: 200, scatter: .random, using: &e))
    }

    /// Nothing to sample, or nothing asked for, gives nothing back rather than
    /// a crash or a made-up point.
    @Test func nothingToSampleGivesNothing() {
        var rng = SplitMix64(seed: 22)
        let flat = Mesh(positions: [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0)],
                        indices: [0, 1, 2])                      // three points in a line
        #expect(surfacePoints(on: Mesh(positions: [], indices: []), count: 10, using: &rng).isEmpty)
        #expect(surfacePoints(on: flat, count: 10, using: &rng).isEmpty)
        #expect(surfacePoints(on: Self.square(), count: 0, using: &rng).isEmpty)
        #expect(surfacePoints(on: Self.square(), spacing: 0, using: &rng).isEmpty)
        #expect(surfacePoints(on: Self.square(), spacing: -1, using: &rng).isEmpty)
        // An index that runs off the end of the positions is skipped, not read.
        let broken = Mesh(positions: [Vector3(0, 0, 0)], indices: [0, 1, 2])
        #expect(broken.surfaceArea == 0)
        #expect(surfacePoints(on: broken, count: 10, using: &rng).isEmpty)
    }

    // MARK: - Support

    /// The smallest and the average distance from a point to its closest
    /// neighbor, by a plain loop over every pair.
    static func nearestNeighborDistance(_ points: [SurfaceSample]) -> (smallest: Double, mean: Double) {
        var smallest = Double.infinity
        var total = 0.0
        for i in points.indices {
            var best = Double.infinity
            for j in points.indices where j != i {
                let d = (points[i].position - points[j].position).lengthSquared
                if d < best { best = d }
            }
            let d = best.squareRoot()
            total += d
            if d < smallest { smallest = d }
        }
        return (smallest, total / Double(points.count))
    }

    /// A direction put through the matrix a placement actually composes.
    static func turn(_ v: Vector3, by placement: MeshInstance) -> Vector3 {
        let m = placement.matrix
        let out = m * SIMD4<Float>(Float(v.x), Float(v.y), Float(v.z), 0)
        return Vector3(Double(out.x), Double(out.y), Double(out.z))
    }
}
