import Foundation
@testable import Ollin
import Testing

/// Pure-CPU checks on `isosurface(at:in:resolution:method:field:)` with
/// `.dualContouring`. The load-bearing ones are what a picture cannot show:
/// that a field's corners land on the corners (the reason the method exists,
/// and the thing marching cubes provably cannot do), that a smooth field stays
/// smooth and round, and that the mesh is closed and winds outward. No GPU.
@Suite
struct DualContouringTests {

    // MARK: Support

    private let box = Box3(min: Vector3(-1.6, -1.6, -1.6), max: Vector3(1.6, 1.6, 1.6))

    /// A block of half-size 1, as the negated box distance so inside is
    /// positive. Its eight corners sit at `(±1, ±1, ±1)`, off the lattice for
    /// every resolution used here.
    private func block(_ p: Vector3) -> Double {
        let q = Vector3(abs(p.x) - 1, abs(p.y) - 1, abs(p.z) - 1)
        let outside = Vector3(max(q.x, 0), max(q.y, 0), max(q.z, 0)).length
        let inside = min(max(q.x, max(q.y, q.z)), 0)
        return -(outside + inside)
    }

    private func sphere(_ p: Vector3) -> Double { 1 - p.length }

    /// A cylinder along y of radius 1 and half-height 0.8: smooth around, a
    /// right-angle crease at each rim.
    private func cylinder(_ p: Vector3) -> Double {
        let radial = (p.x * p.x + p.z * p.z).squareRoot() - 1
        let axial = abs(p.y) - 0.8
        let outside = Vector3(max(radial, 0), max(axial, 0), 0).length
        let inside = min(max(radial, axial), 0)
        return -(outside + inside)
    }

    private func corners() -> [Vector3] {
        var out: [Vector3] = []
        for x in [-1.0, 1.0] { for y in [-1.0, 1.0] { for z in [-1.0, 1.0] { out.append(Vector3(x, y, z)) } } }
        return out
    }

    private func nearestDistance(from target: Vector3, in mesh: Mesh) -> Double {
        mesh.positions.map { ($0 - target).length }.min() ?? .infinity
    }

    /// Every directed edge paired with its reverse: the closed-surface test
    /// that holds even where four quads meet on one segment. Vertices are
    /// matched by position first, since a cell on a crease carries one
    /// vertex per side at the same point and the two faces meeting there
    /// name the shared segment through different ones.
    private func isClosed(_ mesh: Mesh) -> Bool {
        var canonical: [String: Int] = [:]
        let welded = mesh.positions.map { p -> Int in
            let key = "\(p.x),\(p.y),\(p.z)"
            if let index = canonical[key] { return index }
            canonical[key] = canonical.count
            return canonical.count - 1
        }
        var directed: [Int: Int] = [:]
        let n = canonical.count
        for t in stride(from: 0, to: mesh.indices.count, by: 3) {
            let tri = [welded[Int(mesh.indices[t])], welded[Int(mesh.indices[t + 1])], welded[Int(mesh.indices[t + 2])]]
            for e in 0 ..< 3 {
                directed[tri[e] * n + tri[(e + 1) % 3], default: 0] += 1
            }
        }
        for (key, count) in directed {
            let a = key / n, b = key % n
            if directed[b * n + a, default: 0] != count { return false }
        }
        return !directed.isEmpty
    }

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

    // MARK: The corners, the reason the method exists

    /// Every corner of the block has a vertex on it, to within a millionth of
    /// a cell: the crossings on a face are exact for a plane, the normals are
    /// the face normals, and three planes meet at one point.
    @Test func aBlockKeepsItsCorners() {
        let resolution = 20
        let mesh = isosurface(at: 0, in: box, resolution: resolution, method: .dualContouring, field: block)
        let spacing = box.longestSide / Double(resolution)
        for corner in corners() {
            #expect(nearestDistance(from: corner, in: mesh) < spacing * 1e-6)
        }
    }

    /// The counterfactual: the same field through marching cubes has no vertex
    /// within a tenth of a cell of any corner, since its vertices sit on
    /// lattice edges and the corners fall inside cells.
    @Test func marchingCubesRoundsThoseCornersOff() {
        let resolution = 20
        let mesh = isosurface(at: 0, in: box, resolution: resolution, method: .marchingCubes, field: block)
        let spacing = box.longestSide / Double(resolution)
        for corner in corners() {
            #expect(nearestDistance(from: corner, in: mesh) > spacing * 0.1)
        }
    }

    /// A crease keeps its two sides: every vertex on the block has a normal
    /// along one axis, never a blend across an edge.
    @Test func aBlockShadesFlatToItsEdges() {
        let mesh = isosurface(at: 0, in: box, resolution: 20, method: .dualContouring, field: block)
        #expect(!mesh.normals.isEmpty)
        for n in mesh.normals {
            #expect(max(abs(n.x), abs(n.y), abs(n.z)) > 0.9999)
        }
    }

    /// Each corner cell carries three vertices at one point, one per face,
    /// which is what lets the faces shade flat right up to the corner.
    @Test func aCornerCarriesOneVertexPerFace() {
        let mesh = isosurface(at: 0, in: box, resolution: 20, method: .dualContouring, field: block)
        for corner in corners() {
            let there = mesh.positions.indices.filter { (mesh.positions[$0] - corner).length < 1e-9 }
            let distinct = Set(there.map { i -> String in
                let n = mesh.normals[i]
                return "\(Int(n.x.rounded())),\(Int(n.y.rounded())),\(Int(n.z.rounded()))"
            })
            #expect(distinct.count == 3)
        }
    }

    // MARK: A smooth field stays smooth

    /// A sphere comes out round: every vertex within a hundredth of the
    /// radius, at a resolution where a cell spans a tenth of it.
    @Test func aSphereStaysRound() {
        let mesh = isosurface(at: 0, in: box, resolution: 32, method: .dualContouring, field: sphere)
        #expect(mesh.positions.count > 500)
        for p in mesh.positions {
            #expect(abs(p.length - 1) < 0.01)
        }
    }

    /// Coarse, where the normals in one cell spread far enough to look like
    /// a shallow crease, the rank guard keeps the vertex on the surface
    /// instead of sending it toward the center.
    @Test func aCoarseSphereDoesNotDent() {
        let mesh = isosurface(at: 0, in: box, resolution: 10, method: .dualContouring, field: sphere)
        #expect(mesh.positions.count > 50)
        for p in mesh.positions {
            #expect(abs(p.length - 1) < 0.06)
        }
    }

    /// A sphere's normals all point straight out and are shared, one vertex
    /// per cell, since nothing in a cell disagrees.
    @Test func aSphereShadesSmooth() {
        let mesh = isosurface(at: 0, in: box, resolution: 24, method: .dualContouring, field: sphere)
        for (p, n) in zip(mesh.positions, mesh.normals) {
            #expect(n.dot(p.normalized) > 0.995)
        }
        let distinctPositions = Set(mesh.positions.map { "\($0.x),\($0.y),\($0.z)" })
        #expect(distinctPositions.count == mesh.positions.count)
    }

    /// The cylinder's rim: smooth around the side, one normal per side of the
    /// crease, so a rim cell carries a side vertex and a cap vertex at one point.
    @Test func aRimSplitsItsNormals() {
        let mesh = isosurface(at: 0, in: box, resolution: 24, method: .dualContouring, field: cylinder)
        var splitCells = 0
        var byPosition: [String: [Vector3]] = [:]
        for (p, n) in zip(mesh.positions, mesh.normals) {
            byPosition["\(p.x),\(p.y),\(p.z)", default: []].append(n)
        }
        for (_, normals) in byPosition where normals.count >= 2 {
            let spread = normals.map { abs($0.y) }
            if spread.contains(where: { $0 > 0.99 }) && spread.contains(where: { $0 < 0.01 }) { splitCells += 1 }
        }
        #expect(splitCells > 20)
    }

    // MARK: Closed and outward

    @Test func aBlockIsClosedAndWindsOutward() {
        let mesh = isosurface(at: 0, in: box, resolution: 20, method: .dualContouring, field: block)
        #expect(isClosed(mesh))
        #expect(abs(signedVolume(mesh) - 8) < 1e-6)
    }

    @Test func aSphereIsClosedAndHoldsItsVolume() {
        let mesh = isosurface(at: 0, in: box, resolution: 32, method: .dualContouring, field: sphere)
        #expect(isClosed(mesh))
        let volume = signedVolume(mesh)
        #expect(abs(volume - 4 * Double.pi / 3) / (4 * Double.pi / 3) < 0.02)
    }

    /// Every triangle with any area faces the way its shading normals do.
    /// Slivers under a hundredth of a cell's area are left out: three rim
    /// cells whose vertices land almost in a line along the crease make one,
    /// and its orientation is noise on an area nothing can see.
    @Test func everyTriangleFacesTheWayItsNormalsDo() {
        let resolution = 24
        let mesh = isosurface(at: 0, in: box, resolution: resolution, method: .dualContouring, field: cylinder)
        let cellArea = pow(box.longestSide / Double(resolution), 2)
        var wrong = 0, counted = 0
        for t in stride(from: 0, to: mesh.indices.count, by: 3) {
            let i = [Int(mesh.indices[t]), Int(mesh.indices[t + 1]), Int(mesh.indices[t + 2])]
            let a = mesh.positions[i[0]], b = mesh.positions[i[1]], c = mesh.positions[i[2]]
            let face = (b - a).cross(c - a)
            guard face.length / 2 > cellArea * 1e-2 else { continue }
            counted += 1
            let shading = mesh.normals[i[0]] + mesh.normals[i[1]] + mesh.normals[i[2]]
            if face.dot(shading) < 0 { wrong += 1 }
        }
        #expect(counted > 1500)
        #expect(wrong == 0)
    }

    // MARK: The contract

    /// The default path is untouched: no `method` reads as marching cubes.
    @Test func theDefaultIsMarchingCubes() {
        let plain = isosurface(at: 0, in: box, resolution: 18, field: block)
        let marched = isosurface(at: 0, in: box, resolution: 18, method: .marchingCubes, field: block)
        let dual = isosurface(at: 0, in: box, resolution: 18, method: .dualContouring, field: block)
        #expect(plain.positions == marched.positions)
        #expect(plain.indices == marched.indices)
        #expect(plain.positions != dual.positions)
    }

    @Test func dualContouringIsDeterministic() {
        let a = isosurface(at: 0, in: box, resolution: 22, method: .dualContouring, field: cylinder)
        let b = isosurface(at: 0, in: box, resolution: 22, method: .dualContouring, field: cylinder)
        #expect(a.positions == b.positions)
        #expect(a.normals == b.normals)
        #expect(a.indices == b.indices)
    }

    /// A surface that runs out through the box comes back open there, the
    /// way marching cubes leaves it, with no vertex outside the box.
    @Test func aSurfaceLeavingTheBoxComesBackOpen() {
        let mesh = isosurface(at: 0, in: box, resolution: 16, method: .dualContouring) { 2.4 - $0.length }
        #expect(!mesh.indices.isEmpty)
        #expect(!isClosed(mesh))
        for p in mesh.positions {
            #expect(box.contains(p))
        }
    }

    @Test func aFieldThatNeverCrossesHasNoSurface() {
        let mesh = isosurface(at: 0, in: box, resolution: 12, method: .dualContouring) { _ in -1 }
        #expect(mesh.positions.isEmpty)
        #expect(mesh.indices.isEmpty)
    }
}
