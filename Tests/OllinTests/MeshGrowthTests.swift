import Foundation
@testable import Ollin
import Testing

/// Pure-CPU checks on the growing surface and on reaction-diffusion run over a
/// mesh. The load-bearing ones a picture cannot show: that remeshing keeps the
/// surface a closed manifold while its topology churns underneath (every edge
/// still used by exactly two triangles after hundreds of splits, collapses and
/// flips), that the discrete Laplacian matches the operator it claims to be,
/// that growth actually makes area rather than just moving vertices, and that a
/// seeded run reproduces. No GPU.
@Suite
struct MeshGrowthTests {

    // MARK: Support

    /// Every undirected edge of a triangle mesh, and how many triangles use it.
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

    /// The total area of every triangle.
    private func surfaceArea(_ mesh: Mesh) -> Double {
        var total = 0.0
        var i = 0
        while i + 2 < mesh.indices.count {
            let a = mesh.positions[Int(mesh.indices[i])]
            let b = mesh.positions[Int(mesh.indices[i + 1])]
            let c = mesh.positions[Int(mesh.indices[i + 2])]
            total += (b - a).cross(c - a).length * 0.5
            i += 3
        }
        return total
    }

    /// The operators over a mesh's *welded* topology. Ollin's generators emit
    /// flat-shaded geometry whose triangles share no vertices, so anything
    /// measuring a surface property has to weld first, exactly as the growth and
    /// the reaction do.
    private func operators(_ mesh: Mesh) -> (ops: MeshOperators, welded: WeldedMesh) {
        let welded = WeldedMesh(mesh)
        return (MeshOperators(positions: welded.positions, triangles: welded.triangles), welded)
    }

    // MARK: Welding

    /// Ollin's generators emit flat-shaded meshes: an icosphere's triangles each
    /// carry their own three corners, so by index it is thousands of loose
    /// triangles rather than one surface. Welding is what makes it a surface, and
    /// skipping it is invisible in a render while quietly stopping anything from
    /// spreading across the mesh at all.
    @Test
    func generatorMeshesWeldIntoAConnectedSurface() {
        let mesh = Mesh.icosphere(subdivisions: 3)
        // Spelled as a loop rather than a `map` over a range, matching `edgeUse`
        // above: the index arithmetic and the three `Int(...)` conversions in one
        // expression cost enough to type-check that a slower machine gives up on
        // it, and the whole test target then fails to compile.
        var loose: [MeshTriangle] = []
        loose.reserveCapacity(mesh.indices.count / 3)
        var i = 0
        while i + 2 < mesh.indices.count {
            let a = Int(mesh.indices[i]), b = Int(mesh.indices[i + 1]), c = Int(mesh.indices[i + 2])
            loose.append(MeshTriangle(a, b, c))
            i += 3
        }
        let raw = MeshOperators(positions: mesh.positions, triangles: loose)
        // Unwelded, every vertex sees only the two other corners of its own
        // triangle.
        #expect(raw.neighbors.allSatisfy { $0.count == 2 })

        let (ops, welded) = operators(mesh)
        #expect(welded.positions.count < mesh.positions.count / 2,
                "welding merged nothing: \(welded.positions.count) of \(mesh.positions.count)")
        // A sphere built by subdividing an icosahedron has valence 6 everywhere
        // except the twelve original corners, which keep valence 5.
        let valences = ops.neighbors.map(\.count)
        #expect(valences.filter { $0 == 5 }.count == 12)
        #expect(valences.allSatisfy { $0 == 5 || $0 == 6 })
    }

    // MARK: The discrete operators

    /// The Laplacian of a constant field is zero everywhere. This is the
    /// cheapest test that the weights are paired correctly: any row whose
    /// neighbor terms do not cancel against its own would show up here.
    @Test
    func laplacianOfAConstantFieldVanishes() {
        let (ops, welded) = operators(Mesh.icosphere(subdivisions: 2))
        let flat = [Double](repeating: 0.37, count: welded.positions.count)
        for value in ops.laplacian(of: flat) {
            #expect(abs(value) < 1e-9)
        }
    }

    /// The mixed areas partition the surface: summed over every vertex they come
    /// to the mesh's total area. This is the property the obtuse-triangle
    /// fallback exists to preserve, and it fails immediately if the Voronoi and
    /// fallback branches ever double-count or drop a sliver.
    @Test
    func mixedAreasPartitionTheSurface() {
        for subdivisions in [1, 3] {
            let mesh = Mesh.icosphere(subdivisions: subdivisions)
            let (ops, _) = operators(mesh)
            let cells = ops.areas.reduce(0, +)
            let actual = surfaceArea(mesh)
            #expect(abs(cells - actual) / actual < 1e-9,
                    "mixed areas summed to \(cells), surface is \(actual)")
        }
    }

    /// On a unit sphere the mean curvature is 1 everywhere, so the mean-curvature
    /// normal has magnitude 2 and points outward. Pins the operator against a
    /// value known in closed form rather than against its own output.
    @Test
    func meanCurvatureMatchesTheUnitSphere() {
        let (ops, welded) = operators(Mesh.icosphere(radius: 1, subdivisions: 4))
        let curvature = ops.meanCurvatureNormals(of: welded.positions)
        var worst = 0.0
        for v in welded.positions.indices {
            let outward = welded.positions[v].normalized
            worst = Swift.max(worst, abs(curvature[v].dot(outward) - 2))
        }
        // A discretized sphere is slightly faceted, so it reads a touch under 2.
        #expect(worst < 0.02, "mean curvature deviated by \(worst) from the exact 2")
    }

    /// The bound the reaction step sizes its sub-steps from lands near 4 on an
    /// evenly triangulated surface, the same number a square grid's five-point
    /// stencil gives. That equality is what lets feed and kill values carry over
    /// from the texture-space simulation unchanged.
    @Test
    func spectralBoundMatchesAGridStencil() {
        let (ops, _) = operators(Mesh.icosphere(subdivisions: 4))
        #expect(ops.spectralBound > 3.5 && ops.spectralBound < 5.5,
                "bound was \(ops.spectralBound)")
    }

    // MARK: Remeshing keeps the surface sound

    /// The whole point of the remesher: after hundreds of steps of splitting,
    /// collapsing and flipping, every edge is still used by exactly two
    /// triangles. A single unpaired edge means a hole or a fold, and neither is
    /// visible in a render until it catches the light wrong.
    @Test
    func growthKeepsTheSurfaceClosed() {
        let growth = MeshGrowth(mesh: .icosphere(subdivisions: 2), driver: .uniform, seed: 3)
        growth.maxVertices = 3000
        for _ in 0 ..< 60 {
            growth.step()
            let uses = edgeUse(growth.mesh)
            let unpaired = uses.filter { $0.value != 2 }
            #expect(unpaired.isEmpty,
                    "step \(growth.stepCount): \(unpaired.count) edges not shared by two triangles")
            if !unpaired.isEmpty { return }
        }
    }

    /// No triangle degenerates to a sliver or collapses onto a point, and no
    /// vertex index escapes the position array. Both are ways a remeshing bug
    /// shows up as a crash much later rather than at the point of damage.
    @Test
    func growthLeavesNoDegenerateTriangles() {
        let growth = MeshGrowth(mesh: .icosphere(subdivisions: 2), driver: .curvature, seed: 11)
        growth.maxVertices = 2500
        growth.step(50)
        let mesh = growth.mesh
        var i = 0
        while i + 2 < mesh.indices.count {
            let (a, b, c) = (Int(mesh.indices[i]), Int(mesh.indices[i + 1]), Int(mesh.indices[i + 2]))
            #expect(a != b && b != c && c != a, "degenerate triangle at \(i)")
            #expect(a < mesh.positions.count && b < mesh.positions.count && c < mesh.positions.count)
            let area = (mesh.positions[b] - mesh.positions[a])
                .cross(mesh.positions[c] - mesh.positions[a]).length * 0.5
            #expect(area > 1e-12, "zero-area triangle at \(i)")
            i += 3
        }
    }

    /// Edge lengths stay inside the band the remesher promises. Drifting out of
    /// it means the split and collapse thresholds are fighting rather than
    /// converging, which shows up as a mesh that keeps churning without
    /// improving.
    @Test
    func remeshingHoldsEdgeLengthsInBand() {
        let growth = MeshGrowth(mesh: .icosphere(subdivisions: 2), driver: .uniform, seed: 5)
        growth.maxVertices = 3000
        growth.step(40)
        let mesh = growth.mesh
        let target = growth.edgeLength
        var longest = 0.0
        for edge in edgeUse(mesh).keys {
            longest = Swift.max(longest, mesh.positions[edge.low].distance(to: mesh.positions[edge.high]))
        }
        // Growth stretches edges before the next pass splits them, so the
        // ceiling is the split threshold plus one step of stretch, not 4/3.
        #expect(longest < target * 2.2, "longest edge \(longest) against target \(target)")
    }

    // MARK: Growth actually grows

    /// Growth makes surface area. Without this the forces could be moving
    /// vertices around a fixed-size shape and every other test would still pass.
    @Test
    func growthIncreasesSurfaceArea() {
        let growth = MeshGrowth(mesh: .icosphere(subdivisions: 2), driver: .uniform, seed: 1)
        growth.maxVertices = 4000
        let before = surfaceArea(growth.mesh)
        growth.step(40)
        let after = surfaceArea(growth.mesh)
        #expect(after > before * 1.2, "area went \(before) to \(after)")
    }

    /// A field driver that returns zero everywhere grows nothing, so the surface
    /// only relaxes. Pins that growth really is driven by the field rather than
    /// leaking in from the spring rest length.
    @Test
    func aZeroFieldDoesNotGrow() {
        let growth = MeshGrowth(mesh: .icosphere(subdivisions: 2),
                                driver: .field { _, _ in 0 }, seed: 2)
        let before = surfaceArea(growth.mesh)
        growth.step(30)
        let after = surfaceArea(growth.mesh)
        #expect(after < before * 1.05, "a zero field grew area from \(before) to \(after)")
    }

    /// An open sheet keeps its rim: the boundary stays a single closed loop of
    /// edges used by one triangle each. The remesher skips collapses and flips
    /// that touch the rim precisely so this holds.
    @Test
    func anOpenSheetKeepsItsBoundaryLoop() {
        let growth = MeshGrowth(mesh: .plane(width: 2, depth: 2, segments: 8),
                                driver: .uniform, seed: 4)
        growth.maxVertices = 3000
        growth.step(30)
        let uses = edgeUse(growth.mesh)
        let rim = uses.filter { $0.value == 1 }
        #expect(!rim.isEmpty, "the sheet lost its boundary entirely")
        #expect(!uses.contains { $0.value > 2 }, "an edge is shared by more than two triangles")

        // Every rim vertex meets exactly two rim edges, which is what makes the
        // boundary one loop rather than a frayed set of chains.
        var rimDegree: [Int: Int] = [:]
        for edge in rim.keys {
            rimDegree[edge.low, default: 0] += 1
            rimDegree[edge.high, default: 0] += 1
        }
        #expect(rimDegree.values.allSatisfy { $0 == 2 },
                "rim vertices had degrees \(Set(rimDegree.values).sorted())")
    }

    // MARK: Reproducibility

    /// The same seed grows the same form. Everything downstream (a snapshot, an
    /// export recipe, a figure) rests on this.
    @Test
    func aSeededGrowthReproduces() {
        func run() -> [Vector3] {
            let growth = MeshGrowth(mesh: .icosphere(subdivisions: 2), driver: .curvature, seed: 9)
            growth.maxVertices = 1500
            growth.step(25)
            return growth.mesh.positions
        }
        let a = run(), b = run()
        #expect(a.count == b.count)
        for i in a.indices where i < b.count {
            #expect(a[i].distance(to: b[i]) < 1e-12, "vertex \(i) drifted")
        }
    }

    /// Different seeds grow different forms, so the seed is really steering the
    /// symmetry break rather than being ignored.
    @Test
    func differentSeedsDiverge() {
        func run(_ seed: UInt64) -> [Vector3] {
            let growth = MeshGrowth(mesh: .icosphere(subdivisions: 2), driver: .curvature, seed: seed)
            growth.maxVertices = 1500
            growth.step(25)
            return growth.mesh.positions
        }
        let a = run(1), b = run(2)
        let shared = Swift.min(a.count, b.count)
        var moved = 0
        for i in 0 ..< shared where a[i].distance(to: b[i]) > 1e-6 { moved += 1 }
        #expect(moved > shared / 10, "only \(moved) of \(shared) vertices differed between seeds")
    }

    // MARK: Reaction-diffusion on a fixed mesh

    /// A surface with no seed patches stays empty: the reaction cannot invent a
    /// pattern from a uniform substrate, so anything appearing would be noise
    /// leaking from the solver.
    @Test
    func anUnseededReactionStaysBlank() {
        let pattern = MeshReactionDiffusion(mesh: .icosphere(subdivisions: 3),
                                            chemistry: .coral, patches: 0, seed: 1)
        pattern.step(50)
        #expect(pattern.values.allSatisfy { $0 < 1e-6 })
    }

    /// A seeded pattern spreads beyond the vertices it started on, and stays
    /// inside the 0-to-1 range the concentrations are defined on. Running away
    /// past 1 is what an unstable diffusion step looks like.
    @Test
    func aSeededReactionSpreadsAndStaysBounded() {
        let pattern = MeshReactionDiffusion(mesh: .icosphere(subdivisions: 4),
                                            chemistry: .coral, patches: 3, seed: 7)
        let seeded = pattern.values.filter { $0 > 0.1 }.count
        pattern.step(400)
        let after = pattern.values.filter { $0 > 0.1 }.count
        #expect(after > seeded, "pattern did not spread: \(seeded) to \(after)")
        #expect(pattern.values.allSatisfy { $0 >= 0 && $0 <= 1 })
        #expect(pattern.substrate.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    /// Displacement moves vertices along their normals in proportion to the
    /// pattern, and leaves the topology alone.
    @Test
    func displacementFollowsThePattern() {
        let mesh = Mesh.icosphere(subdivisions: 3)
        let pattern = MeshReactionDiffusion(mesh: mesh, chemistry: .coral, patches: 4, seed: 3)
        pattern.step(60)
        let bumped = pattern.displaced(by: 0.2)
        #expect(bumped.indices == mesh.indices)
        for v in mesh.positions.indices {
            let moved = bumped.positions[v].distance(to: mesh.positions[v])
            #expect(abs(moved - pattern.values[v] * 0.2) < 1e-9)
        }
    }

    // MARK: Settling

    /// The point of `settleSteps`: by the first step, a settled growth's
    /// chemistry is already an organized pattern rather than the fresh seed
    /// patches, so growth answers a formed pattern from the start. The probe
    /// that shaped the feature: chemistry settled on the *coarse seed cage*
    /// dies at exactly zero (the patch is a vertex or two wide there), which is
    /// why the settle refines the surface to the target edge length first.
    @Test
    func settleHandsTheChemicalDriverAFormedPattern() {
        func chemistryMeanAfterOneStep(settle: Int) -> Double {
            let growth = MeshGrowth(mesh: .icosphere(radius: 0.75, subdivisions: 3),
                                    driver: .chemical(.coral), edgeLength: 0.085, seed: 5)
            growth.settleSteps = settle
            growth.step(1)
            let chem = growth.chemistry
            return chem.reduce(0, +) / Double(chem.count)
        }
        let fresh = chemistryMeanAfterOneStep(settle: 0)
        let settled = chemistryMeanAfterOneStep(settle: 120)
        #expect(settled > 0, "settled chemistry died, the coarse-cage failure")
        #expect(settled > fresh * 2,
                "settling did not develop the pattern: \(fresh) to \(settled)")
    }

    /// Settling refines and reacts but never grows: after the first step a
    /// heavily settled surface still has essentially the seed's area. It may
    /// sit slightly *under* it (refining a coarse sphere inscribes it, and
    /// relaxation shrinks a touch), but a settle must never add area.
    @Test
    func settleLeavesTheSurfaceUngrown() {
        let seedMesh = Mesh.icosphere(radius: 0.75, subdivisions: 3)
        let growth = MeshGrowth(mesh: seedMesh, driver: .chemical(.coral),
                                edgeLength: 0.085, seed: 5)
        growth.settleSteps = 120
        growth.step(1)
        let before = surfaceArea(seedMesh)
        let after = surfaceArea(growth.mesh)
        #expect(after < before * 1.02,
                "settling grew the surface: \(before) to \(after)")
        #expect(after > before * 0.85,
                "settling collapsed the surface: \(before) to \(after)")
    }

    /// The other drivers have nothing to settle, so the knob leaves them
    /// byte-identical.
    @Test
    func settleLeavesOtherDriversUntouched() {
        func positions(settle: Int) -> [Vector3] {
            let growth = MeshGrowth(mesh: .icosphere(radius: 0.8, subdivisions: 2),
                                    driver: .uniform, edgeLength: 0.2, seed: 9)
            growth.settleSteps = settle
            growth.step(15)
            return growth.mesh.positions
        }
        #expect(positions(settle: 0) == positions(settle: 50))
    }

    /// A settled growth is as reproducible as an unsettled one.
    @Test
    func aSettledGrowthReproduces() {
        func run() -> [Vector3] {
            let growth = MeshGrowth(mesh: .icosphere(radius: 0.8, subdivisions: 2),
                                    driver: .chemical(.coral), edgeLength: 0.16, seed: 11)
            growth.settleSteps = 40
            growth.step(12)
            return growth.mesh.positions
        }
        #expect(run() == run())
    }
}
