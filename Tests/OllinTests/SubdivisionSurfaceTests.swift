import Foundation
@testable import Ollin
import Testing

/// Pure-CPU checks on `Mesh.subdivided(_:levels:)`. The load-bearing ones a
/// picture can't show: that the positional weld recovers shared topology from
/// flat-shaded duplicated vertices (so a box rounds as one surface instead of
/// six drifting plates), that a closed mesh stays watertight through
/// refinement (including across a UV sphere's welded seam and degenerate pole
/// quads), that open rims follow the crease rules instead of shrinking, and
/// that the whole pipeline is deterministic. No GPU.
@Suite
struct SubdivisionSurfaceTests {

    // MARK: Support

    /// Every undirected edge of a triangle mesh, and how many triangles use it.
    private func edgeUse(_ mesh: Mesh) -> [Int: Int] {
        var counts: [Int: Int] = [:]
        let n = mesh.positions.count
        for t in stride(from: 0, to: mesh.indices.count, by: 3) {
            let tri = [Int(mesh.indices[t]), Int(mesh.indices[t + 1]), Int(mesh.indices[t + 2])]
            for e in 0 ..< 3 {
                let a = tri[e], b = tri[(e + 1) % 3]
                counts[min(a, b) * n + max(a, b), default: 0] += 1
            }
        }
        return counts
    }

    /// V - E + F over the triangulated mesh (2 for anything sphere-like).
    private func eulerCharacteristic(_ mesh: Mesh) -> Int {
        var used = Set<Int>()
        for i in mesh.indices { used.insert(Int(i)) }
        return used.count - edgeUse(mesh).count + mesh.triangleCount
    }

    /// The volume the mesh encloses, by the divergence theorem. Positive
    /// means the triangles wind outward.
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

    // MARK: Weld & quad recovery

    @Test func weldRecoversSharedBoxTopology() {
        // A box ships 24 flat-shaded vertices; the weld must find the 8 corners
        // and quad recovery the 6 faces, or subdivision would treat each face
        // as its own open sheet.
        var control = SubdivisionMesh(Mesh.box(size: 1))
        #expect(control.points.count == 8)
        control.recoverQuads()
        #expect(control.faces.count == 6)
        #expect(control.faces.allSatisfy { $0.count == 4 })
    }

    @Test func quadRecoveryFindsGridCells() {
        var control = SubdivisionMesh(Mesh.plane(width: 2, depth: 2, segments: 3))
        control.recoverQuads()
        #expect(control.faces.count == 9)
        #expect(control.faces.allSatisfy { $0.count == 4 })
    }

    // MARK: Catmull-Clark

    @Test func catmullClarkBoxIsWatertightWithKnownCounts() {
        let sub = Mesh.box(size: 1).subdivided(.catmullClark, levels: 1)
        // One level of the welded box: 8 + 6 + 12 = 26 points, 6 * 4 = 24
        // quads = 48 triangles, every edge shared by exactly two.
        #expect(sub.positions.count == 26)
        #expect(sub.triangleCount == 48)
        #expect(edgeUse(sub).values.allSatisfy { $0 == 2 })
        #expect(eulerCharacteristic(sub) == 2)
        #expect(signedVolume(sub) > 0)
    }

    @Test func catmullClarkBoxRoundsAndStaysInside() {
        let sub = Mesh.box(size: 1).subdivided(.catmullClark, levels: 3)
        #expect(edgeUse(sub).values.allSatisfy { $0 == 2 })
        #expect(eulerCharacteristic(sub) == 2)
        // The rules are convex averages: everything stays inside the cage,
        // and the smoothed solid keeps most of the cube's volume.
        let maxCoord = sub.positions.map { max(abs($0.x), max(abs($0.y), abs($0.z))) }.max() ?? 0
        #expect(maxCoord <= 0.5 + 1e-9)
        // The refined volumes shrink toward the limit solid's (measured
        // ~0.333 of the cube) with vanishing steps; a wrong mask shifts the
        // band, a broken weld explodes it.
        let volumes = (1...3).map { signedVolume(Mesh.box(size: 1).subdivided(.catmullClark, levels: $0)) }
        #expect(volumes[0] > volumes[1] && volumes[1] > volumes[2])
        #expect(volumes[2] > 0.30 && volumes[2] < 0.36)
        #expect(volumes[0] - volumes[1] > volumes[1] - volumes[2])
        // Normals point away from the center on a convex solid.
        for (p, n) in zip(sub.positions, sub.normals) {
            #expect(p.normalized.dot(n) > 0)
        }
    }

    @Test func catmullClarkMasksMatchHandComputedValues() {
        // Level 1 of the unit cube, derived by hand from the published rules.
        // A corner (valence 3): Q = mean of its three face points =
        // (1/6, 1/6, 1/6) up to signs, R = mean of its three edge midpoints =
        // (1/3, 1/3, 1/3), S drops out at n = 3, so v' = (Q + 2R)/3 = 5/18
        // per axis. An edge point: (two corners + two face points)/4 =
        // (3/8, 3/8, 0) up to axis. Both must appear exactly.
        let sub = Mesh.box(size: 1).subdivided(.catmullClark, levels: 1)
        let corner = Vector3(5.0 / 18, 5.0 / 18, 5.0 / 18)
        #expect(sub.positions.contains { ($0 - corner).length < 1e-12 })
        let edge = Vector3(0.375, 0.375, 0)
        #expect(sub.positions.contains { ($0 - edge).length < 1e-12 })
    }

    @Test func loopMasksMatchHandComputedValues() {
        // Two flat triangles sharing an interior edge (b, c), everything
        // hand-computable. The odd point on (b, c) must be
        // 3/8 (b + c) + 1/8 (a + d) = (0.8125, 0, 0.525), which differs from
        // the plain midpoint (0.75, 0, 0.5), so a dropped opposite-corner
        // term fails here. The crease rule at b: (6b + a + d)/8 =
        // (1, 0, 0.15). Checked before the limit push (on the raw refine).
        let a = Vector3(0, 0, 0), b = Vector3(1, 0, 0)
        let c = Vector3(0.5, 0, 1), d = Vector3(2, 0, 1.2)
        var control = SubdivisionMesh(Mesh(positions: [a, b, c, d],
                                           indices: [0, 1, 2, 1, 3, 2]))
        control.refineLoop()
        let odd = Vector3(0.8125, 0, 0.525)
        #expect(control.points.contains { ($0 - odd).length < 1e-12 })
        let crease = Vector3(1, 0, 0.15)
        #expect(control.points.contains { ($0 - crease).length < 1e-12 })
        // a and d have a single incident face each: pinned exactly.
        #expect(control.points.contains { ($0 - a).length == 0 })
        #expect(control.points.contains { ($0 - d).length == 0 })
    }

    @Test func sphereSeamAndPolesSurviveSubdivision() {
        // The UV sphere duplicates its seam column (cos 0 vs cos 2π) and
        // degenerates its pole quads; the weld must close the seam and the
        // face cleanup keep the pole fans, or the result leaks.
        let sub = Mesh.sphere(radius: 1, segments: 12, rings: 6).subdivided(.catmullClark, levels: 1)
        #expect(edgeUse(sub).values.allSatisfy { $0 == 2 })
        #expect(eulerCharacteristic(sub) == 2)
        #expect(signedVolume(sub) > 0)
    }

    @Test func catmullClarkHandlesPureTriangleFaces() {
        // A tetrahedron's faces never pair into quads, so this exercises the
        // general n-gon path (a triangle face becomes three quads).
        let sub = Mesh.tetrahedron(radius: 1).subdivided(.catmullClark, levels: 1)
        #expect(sub.positions.count == 4 + 4 + 6)
        #expect(sub.triangleCount == 4 * 3 * 2)
        #expect(edgeUse(sub).values.allSatisfy { $0 == 2 })
        #expect(eulerCharacteristic(sub) == 2)
        #expect(signedVolume(sub) > 0)
    }

    // MARK: Loop

    @Test func loopIcosahedronIsWatertightAndRound() {
        let sub = Mesh.icosahedron(radius: 1).subdivided(.loop, levels: 2)
        #expect(sub.triangleCount == 20 * 16)
        #expect(edgeUse(sub).values.allSatisfy { $0 == 2 })
        #expect(eulerCharacteristic(sub) == 2)
        #expect(signedVolume(sub) > 0)
        // The limit surface sits strictly inside the circumsphere and close
        // to round: the icosahedron's Loop limit is not a sphere, but the
        // radius spread stays narrow.
        let radii = sub.positions.map { $0.length }
        let maxR = radii.max() ?? 0, minR = radii.min() ?? 0
        #expect(maxR < 1.0)
        #expect(minR > 0.6)
        #expect(maxR / minR < 1.2)
        for (p, n) in zip(sub.positions, sub.normals) {
            #expect(p.normalized.dot(n) > 0)
        }
    }

    @Test func loopRegularInteriorMatchesHandComputedMask() {
        // A flat fan: center vertex of valence 6 ringed by its six neighbors
        // on the unit circle, refined one level with no limit push. The even
        // rule at the regular valence must land on (1 - 6β)v + βΣring with
        // β = 1/16; the ring sums to zero, so the center must stay put.
        var positions: [Vector3] = [.zero]
        for k in 0..<6 {
            let a = Double(k) / 6 * 2 * .pi
            positions.append(Vector3(cos(a), 0, sin(a)))
        }
        var indices: [UInt32] = []
        for k in 0..<6 {
            indices.append(contentsOf: [0, UInt32(1 + (k + 1) % 6), UInt32(1 + k)])
        }
        var control = SubdivisionMesh(Mesh(positions: positions, indices: indices))
        control.refineLoop()
        #expect((control.points[0] - .zero).length < 1e-12)
    }

    @Test func extrudedStarStaysWatertightAndFivefoldSymmetric() {
        // An extruded star mixes libtess2 cap triangles with recovered wall
        // quads through the weld; the result must stay closed, and the five
        // points must smooth identically (the cage is 5-fold symmetric, so
        // any asymmetry is a topology bug, not a style).
        let star = Mesh.extrude(Profile.star(points: 5, outerRadius: 1.0, innerRadius: 0.45),
                                depth: 0.6)
        let sub = star.subdivided(.catmullClark, levels: 2)
        #expect(edgeUse(sub).values.allSatisfy { $0 == 2 })
        #expect(eulerCharacteristic(sub) == 2)
        #expect(signedVolume(sub) > 0)
        // The furthest-out point of each of the five arms must sit at the
        // same radius from the axis (within floating error).
        var armReach = [Double](repeating: 0, count: 5)
        for p in sub.positions {
            // Arms sit at π/2 + k · 2π/5 in the outline's plane.
            let angle = atan2(p.y, p.x) - .pi / 2
            let arm = (Int((angle / (2 * .pi / 5)).rounded()) % 5 + 5) % 5
            armReach[arm] = max(armReach[arm], Vector2(p.x, p.y).length)
        }
        // Not exact: the cap positions come back from the tessellator
        // Float-quantized (~1e-8), and the weld keeps them. The bound still
        // pins the real failure, which was a 0.2 spread from asymmetric cap
        // diagonals before the coplanar merge existed.
        let reachMin = armReach.min() ?? 0, reachMax = armReach.max() ?? 1
        #expect(reachMax - reachMin < 1e-6)
    }

    @Test func coplanarMergeRecoversTruePolygonFaces() {
        // A dodecahedron ships each pentagon as a flat fan; quad recovery
        // pairs part of it and the coplanar merge must give back the twelve
        // whole pentagons, so subdivision sees the real topology.
        var control = SubdivisionMesh(Mesh.dodecahedron(radius: 1))
        control.recoverQuads()
        control.mergeCoplanarFaces()
        #expect(control.faces.count == 12)
        #expect(control.faces.allSatisfy { $0.count == 5 })
        // The star extrude: two 10-gon caps plus a wall quad per outline edge.
        var star = SubdivisionMesh(Mesh.extrude(
            Profile.star(points: 5, outerRadius: 1.0, innerRadius: 0.45), depth: 0.6))
        star.recoverQuads()
        star.mergeCoplanarFaces()
        #expect(star.faces.count == 12)
        #expect(star.faces.filter { $0.count == 10 }.count == 2)
        // A deliberately tessellated flat grid has interior vertices, so it
        // must be left exactly alone.
        var grid = SubdivisionMesh(Mesh.plane(width: 2, depth: 2, segments: 3))
        grid.recoverQuads()
        let before = grid.faces
        grid.mergeCoplanarFaces()
        #expect(grid.faces.count == before.count)
    }

    @Test func outputOrientationFollowsInputNormals() {
        // The extrude generator winds inward while shading outward; the
        // subdivided result must follow the normals (outward), which is what
        // the positive volume above pins. Conversely, a mesh with no normals
        // keeps its authored winding: reverse a normal-less box and the
        // smoothed solid stays inward-wound.
        let box = Mesh.box(size: 1)
        var reversed: [UInt32] = []
        var i = 0
        while i + 2 < box.indices.count {
            reversed.append(contentsOf: [box.indices[i], box.indices[i + 2], box.indices[i + 1]])
            i += 3
        }
        let inward = Mesh(positions: box.positions, indices: reversed)
        let sub = inward.subdivided(.catmullClark, levels: 2)
        #expect(signedVolume(sub) < 0)
    }

    // MARK: Open sheets & boundaries

    @Test func flatSheetsStayFlat() {
        // Every rule is an average of coplanar points, so a plane must stay
        // exactly planar under both schemes.
        let cc = Mesh.plane(width: 2, depth: 2, segments: 3).subdivided(.catmullClark, levels: 2)
        #expect(cc.positions.allSatisfy { abs($0.y) < 1e-12 })
        let loop = Mesh.plane(width: 2, depth: 2, segments: 3).subdivided(.loop, levels: 2)
        #expect(loop.positions.allSatisfy { abs($0.y) < 1e-12 })
    }

    @Test func openRimFollowsCreaseRulesAndCornersHold() {
        // Under the quad scheme, the plane's four corners have one incident
        // face each, so they pin; the rim edges are straight, so the crease
        // rule keeps every rim point exactly on the rectangle's outline, and
        // nothing escapes the original footprint.
        let sub = Mesh.plane(width: 2, depth: 2, segments: 2).subdivided(.catmullClark, levels: 2)
        let xs = sub.positions.map(\.x), zs = sub.positions.map(\.z)
        #expect(abs((xs.max() ?? 0) - 1) < 1e-12)
        #expect(abs((xs.min() ?? 0) + 1) < 1e-12)
        #expect(abs((zs.max() ?? 0) - 1) < 1e-12)
        #expect(abs((zs.min() ?? 0) + 1) < 1e-12)
        let corners = sub.positions.filter { abs(abs($0.x) - 1) < 1e-12 && abs(abs($0.z) - 1) < 1e-12 }
        #expect(corners.count == 4)
    }

    @Test func openCylinderKeepsItsTwoRims() {
        // A capless cylinder has two open rims; each must stay a rim (edges
        // used once) rather than being sewn shut or shrunk away.
        let sub = Mesh.cylinder(radius: 1, height: 2, segments: 12, caps: false)
            .subdivided(.catmullClark, levels: 2)
        let boundaryEdges = edgeUse(sub).values.filter { $0 == 1 }.count
        #expect(boundaryEdges > 0)
        #expect(edgeUse(sub).values.allSatisfy { $0 <= 2 })
        // Rim vertices stay at the cylinder's full half-height (the crease
        // rule runs along the circular rim, never down the wall).
        let topRim = sub.positions.filter { abs($0.y - 1) < 1e-9 }
        #expect(!topRim.isEmpty)
    }

    // MARK: Guards & determinism

    @Test func zeroLevelsAndEmptyMeshesPassThrough() {
        let box = Mesh.box(size: 1)
        let same = box.subdivided(levels: 0)
        #expect(same.positions.count == box.positions.count)
        #expect(same.indices == box.indices)
        let empty = Mesh(positions: [], indices: []).subdivided(levels: 3)
        #expect(empty.isEmpty)
    }

    @Test func subdivisionIsDeterministic() {
        let a = Mesh.sphere(radius: 1, segments: 10, rings: 5).subdivided(.catmullClark, levels: 2)
        let b = Mesh.sphere(radius: 1, segments: 10, rings: 5).subdivided(.catmullClark, levels: 2)
        #expect(a.indices == b.indices)
        #expect(zip(a.positions, b.positions).allSatisfy { ($0 - $1).length == 0 })
        let c = Mesh.icosahedron(radius: 1).subdivided(.loop, levels: 3)
        let d = Mesh.icosahedron(radius: 1).subdivided(.loop, levels: 3)
        #expect(c.indices == d.indices)
        #expect(zip(c.positions, d.positions).allSatisfy { ($0 - $1).length == 0 })
    }

    @Test func materialCarriesOverAndUVsDrop() {
        var mesh = Mesh.sphere(radius: 1, segments: 8, rings: 4)
        mesh.material = MeshMaterial(baseColor: .red)
        let sub = mesh.subdivided(levels: 1)
        #expect(sub.material != nil)
        #expect(sub.uvs.isEmpty)
        #expect(sub.normals.count == sub.positions.count)
    }

    /// A cage painted red on one side and blue on the other keeps its colors through
    /// refinement, and they *smooth* rather than stepping: the surface between the two
    /// halves has to pass through the mixtures, and no vertex may invent a color
    /// outside the range its cage spanned (every mask is a convex combination).
    @Test func vertexColorsRefineAlongWithPositions() {
        var cage = Mesh.box(size: 2)
        cage.colors = cage.positions.map { $0.x < 0 ? Color.red : Color.blue }
        let sub = cage.subdivided(.catmullClark, levels: 2)

        #expect(sub.colors.count == sub.positions.count)
        // Convex combinations only: red and blue both stay off, green never appears.
        #expect(sub.colors.allSatisfy { $0.green <= 1e-9 })
        #expect(sub.colors.allSatisfy { $0.red >= -1e-9 && $0.red <= 1 + 1e-9 })
        // The two originals survive somewhere, and the seam carries genuine mixtures
        // (a nearest-neighbor transfer would give only the two endpoint colors).
        #expect(sub.colors.contains { $0.red > 0.9 })
        #expect(sub.colors.contains { $0.blue > 0.9 })
        #expect(sub.colors.contains { $0.red > 0.2 && $0.red < 0.8 })
        // Color follows position: the reddest vertices sit on the cage's red side.
        let reddest = zip(sub.positions, sub.colors).filter { $0.1.red > 0.9 }
        #expect(!reddest.isEmpty && reddest.allSatisfy { $0.0.x < 0 })
    }

    /// The same through the Loop scheme, whose limit push touches colors too.
    @Test func loopCarriesVertexColors() {
        var cage = Mesh.icosahedron(radius: 1)
        cage.colors = cage.positions.map { $0.y < 0 ? Color.black : Color.white }
        let sub = cage.subdivided(.loop, levels: 2)
        #expect(sub.colors.count == sub.positions.count)
        #expect(sub.colors.contains { $0.red > 0.2 && $0.red < 0.8 })
        let dark = zip(sub.positions, sub.colors).filter { $0.1.red < 0.15 }
        #expect(!dark.isEmpty && dark.allSatisfy { $0.0.y < 0.15 })
    }

    /// A mesh with no colors must come back with none: an empty `colors` is the
    /// constant-color render path, so refinement must not fill it in.
    @Test func aColorlessCageStaysColorless() {
        let plain = Mesh.box(size: 1)
        #expect(plain.colors.isEmpty)
        #expect(plain.subdivided(.catmullClark, levels: 2).colors.isEmpty)
        #expect(Mesh.icosahedron(radius: 1).subdivided(.loop, levels: 2).colors.isEmpty)
    }

    /// Colors ride along without disturbing the geometry: the same cage with and
    /// without them refines to exactly the same positions and indices.
    @Test func colorsDoNotMoveTheSurface() {
        let plain = Mesh.box(size: 2)
        var painted = plain
        painted.colors = plain.positions.map { $0.x < 0 ? Color.red : Color.blue }
        let a = plain.subdivided(.catmullClark, levels: 2)
        let b = painted.subdivided(.catmullClark, levels: 2)
        #expect(a.indices == b.indices)
        #expect(zip(a.positions, b.positions).allSatisfy { ($0 - $1).length == 0 })
    }
}
