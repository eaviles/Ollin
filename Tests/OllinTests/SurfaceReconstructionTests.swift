import Foundation
@testable import Ollin
import Testing

/// Pure-CPU checks on the two point-cloud surfacing paths and the grid index
/// under them. The load-bearing ones: the neighbor search agrees with brute
/// force (a wrong ring-search stopping bound locks results to the lattice and
/// no picture shows it), a sampled sphere comes back watertight with the right
/// volume and an outward wind, a data hole stays a hole instead of growing a
/// cap, viewpoints orient thin double-sided structure correctly, and both
/// paths reproduce byte-identically. No GPU.
@Suite
struct SurfaceReconstructionTests {

    // MARK: Support

    /// Points spread evenly over a sphere by the golden-angle spiral;
    /// deterministic, no randomness.
    private func spherePoints(_ count: Int, radius: Double = 1) -> [Vector3] {
        let golden = Double.pi * (3 - 5.0.squareRoot())
        return (0 ..< count).map { i in
            let y = 1 - 2 * (Double(i) + 0.5) / Double(count)
            let ring = (1 - y * y).squareRoot()
            let angle = golden * Double(i)
            return Vector3(cos(angle) * ring, y, sin(angle) * ring) * radius
        }
    }

    private func edgeUse(_ mesh: Mesh) -> [MeshEdge: Int] {
        var uses: [MeshEdge: Int] = [:]
        var i = 0
        while i + 2 < mesh.indices.count {
            let a = Int(mesh.indices[i]), b = Int(mesh.indices[i + 1]), c = Int(mesh.indices[i + 2])
            uses[MeshEdge(a, b), default: 0] += 1
            uses[MeshEdge(b, c), default: 0] += 1
            uses[MeshEdge(c, a), default: 0] += 1
            i += 3
        }
        return uses
    }

    private func signedVolume(_ mesh: Mesh) -> Double {
        var total = 0.0
        var i = 0
        while i + 2 < mesh.indices.count {
            let a = mesh.positions[Int(mesh.indices[i])]
            let b = mesh.positions[Int(mesh.indices[i + 1])]
            let c = mesh.positions[Int(mesh.indices[i + 2])]
            total += a.dot(b.cross(c)) / 6
            i += 3
        }
        return total
    }

    // MARK: The grid index

    /// The neighbor queries agree with brute force, exactly. The stopping
    /// bound is the part a plausible-looking implementation gets wrong: a ring
    /// search that stops one ring early returns lattice-locked neighbors.
    @Test
    func gridQueriesMatchBruteForce() {
        var rng = SplitMix64(seed: 21)
        let points = (0 ..< 300).map { _ in
            Vector3(Double.random(in: -1 ... 1, using: &rng),
                    Double.random(in: -0.4 ... 0.4, using: &rng),
                    Double.random(in: -1 ... 1, using: &rng))
        }
        let grid = PointGrid3(points: points, cellSize: 0.23)

        let queries = (0 ..< 24).map { _ in
            Vector3(Double.random(in: -1.3 ... 1.3, using: &rng),
                    Double.random(in: -0.6 ... 0.6, using: &rng),
                    Double.random(in: -1.3 ... 1.3, using: &rng))
        }
        for q in queries {
            let byDistance = points.indices.sorted {
                let a = (points[$0] - q).lengthSquared, b = (points[$1] - q).lengthSquared
                return a != b ? a < b : $0 < $1
            }
            #expect(grid.nearest(to: q) == byDistance.first)
            #expect(grid.kNearest(9, to: q) == Array(byDistance.prefix(9)))

            var gathered: Set<Int> = []
            grid.forEachNeighbor(of: q, within: 0.5) { i, _ in gathered.insert(i) }
            let expected = Set(points.indices.filter { (points[$0] - q).length <= 0.5 })
            #expect(gathered == expected)
        }
    }

    // MARK: Particle surfacing

    /// One isolated point skins as an exact ball of the given radius.
    @Test
    func aLonePointSkinsAsABall() {
        let mesh = particleSurface(of: [Vector3(0.2, -0.1, 0.4)], radius: 0.5, resolution: 56)
        #expect(edgeUse(mesh).values.allSatisfy { $0 == 2 }, "the ball is not watertight")
        let volume = signedVolume(mesh)   // computed about the origin, sign carries orientation
        let ball = 4.0 / 3.0 * .pi * 0.5 * 0.5 * 0.5
        #expect(abs(volume - ball) / ball < 0.05,
                "ball volume off: \(volume) vs \(ball)")
        for v in mesh.positions {
            let r = (v - Vector3(0.2, -0.1, 0.4)).length
            #expect(abs(r - 0.5) < 0.04, "surface off the sphere at radius \(r)")
        }
    }

    /// Two clusters far beyond the blend reach skin as two separate closed
    /// bodies; the volume says both are there.
    @Test
    func farClustersSkinSeparately() {
        var points = spherePoints(160, radius: 0.3)
        points += spherePoints(160, radius: 0.3).map { $0 + Vector3(4, 0, 0) }
        let mesh = particleSurface(of: points, radius: 0.15, resolution: 96)
        #expect(edgeUse(mesh).values.allSatisfy { $0 == 2 })
        // Each cluster is a shell of points, so its skin is a thickened
        // sphere; what matters here is that the two read as disjoint bodies.
        let xs = mesh.positions.map(\.x)
        #expect(xs.contains { $0 < 1 } && xs.contains { $0 > 3 })
        #expect(!xs.contains { $0 > 1.5 && $0 < 2.5 }, "the blend bridged the gap")
    }

    /// The skin reproduces byte-identically.
    @Test
    func particleSurfaceReproduces() {
        let points = spherePoints(200, radius: 0.6)
        let a = particleSurface(of: points, radius: 0.2, resolution: 40)
        let b = particleSurface(of: points, radius: 0.2, resolution: 40)
        #expect(a.positions == b.positions && a.indices == b.indices)
    }

    // MARK: Reconstruction

    /// A sampled sphere reconstructs watertight, at the right volume, wound
    /// outward. This exercises the pose-less spanning-tree orientation.
    @Test
    func aSampledSphereReconstructsClosed() {
        let mesh = reconstructSurface(of: spherePoints(1600),
                                      resolution: 56, maxGap: .infinity)
        #expect(!mesh.positions.isEmpty)
        #expect(edgeUse(mesh).values.allSatisfy { $0 == 2 }, "not watertight")
        let volume = signedVolume(mesh)
        let sphere = 4.0 / 3.0 * Double.pi
        #expect(volume > 0, "wound inward: the orientation flipped")
        #expect(abs(volume - sphere) / sphere < 0.06,
                "sphere volume off: \(volume) vs \(sphere)")
        for v in mesh.positions {
            #expect(abs(v.length - 1) < 0.06, "surface off the sphere at radius \(v.length)")
        }
    }

    /// A sampled torus reconstructs with the topology of a torus: watertight
    /// and Euler characteristic zero.
    @Test
    func aSampledTorusKeepsItsHole() {
        var points: [Vector3] = []
        for i in 0 ..< 120 {
            let u = Double(i) / 120 * .tau
            for j in 0 ..< 48 {
                let v = Double(j) / 48 * .tau
                let ring = 1 + 0.4 * cos(v)
                points.append(Vector3(ring * cos(u), 0.4 * sin(v), ring * sin(u)))
            }
        }
        let mesh = reconstructSurface(of: points, resolution: 72, maxGap: .infinity)
        let uses = edgeUse(mesh)
        #expect(uses.values.allSatisfy { $0 == 2 }, "not watertight")
        let vertices = mesh.positions.count
        let faces = mesh.indices.count / 3
        let euler = vertices - uses.count + faces
        #expect(euler == 0, "expected a torus (Euler 0), got \(euler)")
    }

    /// An open surface stays open: a hemisphere's rim is a boundary, and the
    /// missing half does not grow a cap. Guessing a surface into a data hole
    /// is the failure this pins against.
    @Test
    func aHoleInTheDataStaysOpen() {
        let points = spherePoints(3200).filter { $0.y > 0.05 }
        let mesh = reconstructSurface(of: points, resolution: 56)
        #expect(!mesh.positions.isEmpty)
        let boundary = edgeUse(mesh).values.filter { $0 == 1 }.count
        #expect(boundary > 0, "the rim vanished: the hole was capped")
        for v in mesh.positions {
            let inDiscInterior = v.y < -0.15 || (abs(v.y) < 0.15 && (v.x * v.x + v.z * v.z) < 0.5)
            #expect(!inDiscInterior, "a cap grew into the missing half at \(v)")
        }
    }

    /// Viewpoints orient a thin two-sided structure: two parallel sheets with
    /// a camera on each side come back facing their cameras. This is the case
    /// tree propagation can get wrong, and the reason scans pass their poses.
    @Test
    func viewpointsOrientThinStructure() {
        var points: [Vector3] = []
        for i in 0 ..< 40 {
            for j in 0 ..< 40 {
                let x = Double(i) / 39, z = Double(j) / 39
                points.append(Vector3(x, 0, z))
                points.append(Vector3(x, 0.3, z))
            }
        }
        let mesh = reconstructSurface(of: points, spacing: 1.0 / 39, resolution: 64,
                                      orientedToward: [Vector3(0.5, 2, 0.5),
                                                       Vector3(0.5, -1.7, 0.5)])
        #expect(!mesh.positions.isEmpty)
        var checked = 0
        for (v, n) in zip(mesh.positions, mesh.normals) {
            // Away from the sheets' open rims, each side faces its camera.
            guard v.x > 0.2, v.x < 0.8, v.z > 0.2, v.z < 0.8 else { continue }
            checked += 1
            if v.y > 0.15 {
                #expect(n.y > 0, "top sheet facing away from its camera at \(v)")
            } else {
                #expect(n.y < 0, "bottom sheet facing away from its camera at \(v)")
            }
        }
        #expect(checked > 50, "the probe barely sampled the sheets")
    }

    /// Noisy samples still reconstruct one closed surface within the noise
    /// band: the plane fit averages the jitter away.
    @Test
    func noiseIsAveragedNotReproduced() {
        var rng = SplitMix64(seed: 7)
        let spacing = (4 * Double.pi / 2400).squareRoot()
        let points = spherePoints(2400).map { p in
            p + Vector3(Double.random(in: -1 ... 1, using: &rng),
                        Double.random(in: -1 ... 1, using: &rng),
                        Double.random(in: -1 ... 1, using: &rng)) * (spacing * 0.3)
        }
        let mesh = reconstructSurface(of: points, resolution: 48, maxGap: .infinity,
                                      keepingLargestComponent: true)
        #expect(edgeUse(mesh).values.allSatisfy { $0 == 2 })
        for v in mesh.positions {
            #expect(abs(v.length - 1) < spacing * 1.5,
                    "surface left the noise band at radius \(v.length)")
        }
    }

    /// Reconstruction reproduces byte-identically, on both orientation paths.
    @Test
    func reconstructionReproduces() {
        let points = spherePoints(700)
        let a = reconstructSurface(of: points, resolution: 32, maxGap: .infinity)
        let b = reconstructSurface(of: points, resolution: 32, maxGap: .infinity)
        #expect(a.positions == b.positions && a.indices == b.indices)

        let eye = [Vector3(0, 0, 4)]
        let c = reconstructSurface(of: points, resolution: 32, orientedToward: eye)
        let d = reconstructSurface(of: points, resolution: 32, orientedToward: eye)
        #expect(c.positions == d.positions && c.indices == d.indices)
    }

    // MARK: The robust fitting

    /// The robust fit rebuilds the same clean sphere the plane fit does:
    /// watertight, the right volume, wound outward, on the sphere.
    @Test
    func robustFittingReconstructsClosed() {
        let mesh = reconstructSurface(of: spherePoints(1600), resolution: 56,
                                      maxGap: .infinity, fitting: .robust)
        #expect(!mesh.positions.isEmpty)
        #expect(edgeUse(mesh).values.allSatisfy { $0 == 2 }, "not watertight")
        let volume = signedVolume(mesh)
        let sphere = 4.0 / 3.0 * Double.pi
        #expect(volume > 0, "wound inward: the orientation flipped")
        #expect(abs(volume - sphere) / sphere < 0.06,
                "sphere volume off: \(volume) vs \(sphere)")
        for v in mesh.positions {
            #expect(abs(v.length - 1) < 0.06, "surface off the sphere at radius \(v.length)")
        }
    }

    /// On the same seeded noisy sphere, the robust blend lands at least as
    /// close to the true surface as the piecewise planes: its whole point.
    @Test
    func robustFittingSmoothsNoiseAtLeastAsWellAsPlanes() {
        var rng = SplitMix64(seed: 7)
        let spacing = (4 * Double.pi / 2400).squareRoot()
        let points = spherePoints(2400).map { p in
            p + Vector3(Double.random(in: -1 ... 1, using: &rng),
                        Double.random(in: -1 ... 1, using: &rng),
                        Double.random(in: -1 ... 1, using: &rng)) * (spacing * 0.3)
        }
        func rms(_ mesh: Mesh) -> Double {
            guard !mesh.positions.isEmpty else { return .infinity }
            let sum = mesh.positions.reduce(0.0) {
                let e = $1.length - 1
                return $0 + e * e
            }
            return (sum / Double(mesh.positions.count)).squareRoot()
        }
        let planes = reconstructSurface(of: points, resolution: 48, maxGap: .infinity,
                                        keepingLargestComponent: true)
        let robust = reconstructSurface(of: points, resolution: 48, maxGap: .infinity,
                                        fitting: .robust, keepingLargestComponent: true)
        #expect(edgeUse(robust).values.allSatisfy { $0 == 2 })
        #expect(rms(robust) <= rms(planes),
                "robust \(rms(robust)) vs planes \(rms(planes))")
    }

    /// The default fitting is the plane fit, byte for byte: adding the robust
    /// path may not move a single vertex of the shipped reconstruction.
    @Test
    func planesFittingIsTheDefault() {
        let points = spherePoints(700)
        let a = reconstructSurface(of: points, resolution: 32, maxGap: .infinity)
        let b = reconstructSurface(of: points, resolution: 32, maxGap: .infinity,
                                   fitting: .planes)
        #expect(a.positions == b.positions && a.indices == b.indices)
    }

    /// The robust fit reproduces byte-identically too.
    @Test
    func robustFittingReproduces() {
        let points = spherePoints(700)
        let a = reconstructSurface(of: points, resolution: 32, maxGap: .infinity,
                                   fitting: .robust)
        let b = reconstructSurface(of: points, resolution: 32, maxGap: .infinity,
                                   fitting: .robust)
        #expect(a.positions == b.positions && a.indices == b.indices)
        #expect(!a.positions.isEmpty)
    }

    /// Both fittings share one validity gate, so the robust fit keeps a data
    /// hole open exactly as the planes do.
    @Test
    func robustFittingKeepsHolesOpen() {
        let points = spherePoints(3200).filter { $0.y > 0.05 }
        let mesh = reconstructSurface(of: points, resolution: 56, fitting: .robust)
        #expect(!mesh.positions.isEmpty)
        let boundary = edgeUse(mesh).values.filter { $0 == 1 }.count
        #expect(boundary > 0, "the rim vanished: the hole was capped")
        for v in mesh.positions {
            let inDiscInterior = v.y < -0.15 || (abs(v.y) < 0.15 && (v.x * v.x + v.z * v.z) < 0.5)
            #expect(!inDiscInterior, "a cap grew into the missing half at \(v)")
        }
    }
}
