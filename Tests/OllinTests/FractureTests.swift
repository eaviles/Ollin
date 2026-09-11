import Foundation
import Ollin
import Testing

/// Pure-CPU checks on breaking a shape and a solid into pieces: the pieces put
/// back together are the original (area in 2D, volume in 3D), no two of them
/// overlap, every 3D piece is convex, a break around a point leaves its small
/// chips there, and one seed always gives one break. The 3D convex hull the
/// solid break stands on is checked here too. No GPU.
@Suite
struct FractureTests {

    // MARK: - Shapes

    private func square(_ size: Double) -> Shape {
        Shape([Vector2(0, 0), Vector2(size, 0), Vector2(size, size), Vector2(0, size)])
    }

    private func disk(radius: Double, steps: Int = 64) -> Shape {
        Shape((0 ..< steps).map { i in
            let a = Double(i) / Double(steps) * 2 * .pi
            return Vector2(cos(a), sin(a)) * radius
        })
    }

    @Test func piecesPutBackTogetherAreTheShape() {
        let tile = square(300)
        let pieces = tile.fractured(into: 14, seed: 7)
        #expect(pieces.count > 1)
        #expect(pieces.count <= 14)
        let sum = pieces.reduce(0) { $0 + $1.area }
        #expect(abs(sum - tile.area) < tile.area * 1e-6)
        #expect(pieces.allSatisfy { $0.area > 0 })
    }

    @Test func everyPieceLiesInsideTheShape() {
        let tile = disk(radius: 160)
        for piece in tile.fractured(into: 12, seed: 3) {
            let inside = piece.centroid
            #expect(tile.contains(inside), "a piece's own middle fell outside the shape")
            #expect(piece.separated().count == 1, "a piece came back as two islands")
        }
    }

    @Test func noTwoPiecesOverlap() {
        let pieces = disk(radius: 200).fractured(into: 10, seed: 11)
        for i in pieces.indices {
            for j in pieces.indices where j > i {
                let shared = pieces[i].intersection(pieces[j]).area
                #expect(shared < pieces[i].area * 1e-6, "pieces \(i) and \(j) cover the same ground")
            }
        }
    }

    @Test func oneSeedIsOneBreak() {
        let tile = square(240)
        let once = tile.fractured(into: 9, seed: 42)
        let again = tile.fractured(into: 9, seed: 42)
        #expect(once == again)
        let other = tile.fractured(into: 9, seed: 43)
        #expect(once != other)
    }

    @Test func aBreakAroundAPointChipsThere() {
        let tile = square(400)
        let impact = Vector2(60, 60)
        let pieces = tile.fractured(into: 24, around: impact, seed: 5)
        let near = pieces.filter { $0.centroid.distance(to: impact) < 120 }
        let far = pieces.filter { $0.centroid.distance(to: impact) > 260 }
        #expect(!near.isEmpty && !far.isEmpty)
        let nearMean = near.reduce(0) { $0 + $1.area } / Double(near.count)
        let farMean = far.reduce(0) { $0 + $1.area } / Double(far.count)
        #expect(nearMean < farMean * 0.5, "the chips at the blow are not the small ones")
    }

    @Test func aShapeWithAHoleKeepsIt() {
        let outer = (0 ..< 64).map { i -> Vector2 in
            let a = Double(i) / 64 * 2 * .pi
            return Vector2(cos(a), sin(a)) * 200
        }
        let hole = (0 ..< 64).map { i -> Vector2 in
            let a = Double(i) / 64 * 2 * .pi
            return Vector2(cos(a), sin(a)) * 90
        }
        let ring = Shape(outer: outer, holes: [hole])
        let pieces = ring.fractured(into: 16, seed: 2)
        let sum = pieces.reduce(0) { $0 + $1.area }
        #expect(abs(sum - ring.area) < ring.area * 1e-5)
        // Nothing lands in the hole.
        for piece in pieces {
            #expect(piece.centroid.length > 80, "a piece grew into the hole")
        }
    }

    @Test func askingForOnePieceGivesTheShapeBack() {
        let tile = square(100)
        #expect(tile.fractured(into: 1, seed: 0) == [tile])
        #expect(Shape(contours: []).fractured(into: 8, seed: 0).isEmpty)
    }

    @Test func aConcaveShapeBreaksIntoSingleIslands() {
        // An L: a cell straddling the notch would come back as two islands, and
        // each island has to be its own piece.
        let l = Shape([Vector2(0, 0), Vector2(300, 0), Vector2(300, 100),
                       Vector2(100, 100), Vector2(100, 300), Vector2(0, 300)])
        let pieces = l.fractured(into: 18, seed: 9)
        #expect(pieces.allSatisfy { $0.separated().count == 1 })
        let sum = pieces.reduce(0) { $0 + $1.area }
        #expect(abs(sum - l.area) < l.area * 1e-5)
    }

    // MARK: - Shape measurements

    @Test func aRingMeasuresAsTheDifferenceOfItsCircles() {
        let outer = (0 ..< 128).map { i -> Vector2 in
            let a = Double(i) / 128 * 2 * .pi
            return Vector2(cos(a), sin(a)) * 100 + Vector2(50, 50)
        }
        let hole = (0 ..< 128).map { i -> Vector2 in
            let a = Double(i) / 128 * 2 * .pi
            return Vector2(cos(a), -sin(a)) * 40 + Vector2(50, 50)
        }
        let ring = Shape(outer: outer, holes: [hole])
        let expected = Double.pi * (100.0 * 100.0 - 40.0 * 40.0)
        #expect(abs(ring.area - expected) < expected * 0.01)
        #expect(ring.centroid.distance(to: Vector2(50, 50)) < 1e-6)
    }

    @Test func separatedSplitsTwoIslandsAndKeepsTheirHoles() {
        let left = Shape(outer: [Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)],
                         holes: [[Vector2(30, 30), Vector2(70, 30), Vector2(70, 70), Vector2(30, 70)]])
        let right = Shape([Vector2(200, 0), Vector2(300, 0), Vector2(300, 100), Vector2(200, 100)])
        let both = Shape(contours: left.contours + right.contours)
        let islands = both.separated()
        #expect(islands.count == 2)
        #expect(islands.contains { $0.contours.count == 2 })
        #expect(abs(islands.reduce(0) { $0 + $1.area } - both.area) < 1e-6)
    }

    // MARK: - The hull under the solid break

    @Test func theHullOfABoxIsTheBox() {
        var points = Mesh.box(size: 2).positions
        var rng = SplitMix64(seed: 4)
        // Points inside the box change nothing: the hull already contains them.
        for _ in 0 ..< 200 {
            points.append(Vector3(Double.random(in: -0.9 ... 0.9, using: &rng),
                                  Double.random(in: -0.9 ... 0.9, using: &rng),
                                  Double.random(in: -0.9 ... 0.9, using: &rng)))
        }
        let hull = convexHull(of: points)
        #expect(abs(hull.volume - 8) < 1e-6)
        #expect(hull.positions.allSatisfy { abs($0.x) > 0.99 || abs($0.y) > 0.99 || abs($0.z) > 0.99 })
    }

    @Test func aFlatCloudEnclosesNothing() {
        let flat = (0 ..< 50).map { i in Vector3(Double(i), Double(i * i % 7), 0) }
        #expect(convexHull(of: flat).isEmpty)
        #expect(convexHull(of: [Vector3.zero, .unitX, .unitY]).isEmpty)
    }

    @Test func theHullOfASphereIsTheSphere() {
        let ball = Mesh.icosphere(radius: 1, subdivisions: 2)
        let hull = convexHull(of: ball.positions)
        #expect(abs(hull.volume - ball.volume) < ball.volume * 1e-6)
    }

    // MARK: - Solids

    @Test func piecesPutBackTogetherAreTheSolid() {
        let block = Mesh.box(size: 1)
        let pieces = block.fractured(into: 12, seed: 7)
        #expect(pieces.count > 1)
        let sum = pieces.reduce(0) { $0 + $1.volume }
        #expect(abs(sum - block.volume) < block.volume * 1e-6)
    }

    @Test func everyPieceIsConvex() {
        for piece in Mesh.icosphere(radius: 0.5, subdivisions: 1).fractured(into: 8, seed: 3) {
            let hull = convexHull(of: piece.positions)
            #expect(abs(hull.volume - piece.volume) < piece.volume * 1e-4,
                    "a piece holds a dent its own hull would fill")
        }
    }

    @Test func noTwoSolidPiecesOverlap() {
        let pieces = Mesh.box(size: 1).fractured(into: 10, seed: 21)
        for i in pieces.indices {
            let inside = pieces[i].centroid
            for j in pieces.indices where j != i {
                // A point inside one convex piece must be outside every other,
                // which for a convex solid is one plane test per face.
                #expect(!FractureTests.contains(pieces[j], inside),
                        "piece \(j) swallowed the middle of piece \(i)")
            }
        }
    }

    @Test func oneSeedIsOneSolidBreak() {
        let block = Mesh.box(size: 1)
        let once = block.fractured(into: 9, seed: 8)
        let again = block.fractured(into: 9, seed: 8)
        #expect(once.map(\.positions) == again.map(\.positions))
        let other = block.fractured(into: 9, seed: 9)
        #expect(once.map(\.positions) != other.map(\.positions))
    }

    @Test func aSolidBreakAroundAPointChipsThere() {
        let block = Mesh.box(size: 2)
        let impact = Vector3(-0.9, -0.9, -0.9)
        let pieces = block.fractured(into: 24, around: impact, seed: 4)
        let near = pieces.filter { $0.centroid.distance(to: impact) < 0.8 }
        let far = pieces.filter { $0.centroid.distance(to: impact) > 1.8 }
        #expect(!near.isEmpty && !far.isEmpty)
        let nearMean = near.reduce(0) { $0 + $1.volume } / Double(near.count)
        let farMean = far.reduce(0) { $0 + $1.volume } / Double(far.count)
        #expect(nearMean < farMean * 0.5, "the chips at the blow are not the small ones")
    }

    @Test func aPieceCarriesTheMaterialAndDrawsFacingOut() {
        var block = Mesh.box(size: 1)
        block.material = MeshMaterial(baseColor: .red)
        let pieces = block.fractured(into: 6, seed: 1)
        #expect(pieces.allSatisfy { $0.material?.baseColor == Color.red })
        // Outward-facing triangles: the signed volume of every piece is positive.
        for piece in pieces {
            #expect(FractureTests.signedVolume(piece) > 0, "a piece is inside out")
        }
    }

    @Test func askingForOneSolidPieceGivesTheMeshBack() {
        let block = Mesh.box(size: 1)
        #expect(block.fractured(into: 1, seed: 0).count == 1)
        #expect(Mesh(positions: [], indices: []).fractured(into: 8, seed: 0).isEmpty)
    }

    /// The volume the triangles enclose, signed by which way they face.
    private static func signedVolume(_ mesh: Mesh) -> Double {
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

    /// Whether a convex mesh contains a point, by testing it against every
    /// face's plane.
    private static func contains(_ mesh: Mesh, _ point: Vector3) -> Bool {
        var i = 0
        while i + 2 < mesh.indices.count {
            let a = mesh.positions[Int(mesh.indices[i])]
            let b = mesh.positions[Int(mesh.indices[i + 1])]
            let c = mesh.positions[Int(mesh.indices[i + 2])]
            let normal = (b - a).cross(c - a)
            if normal.dot(point - a) > 1e-9 * Swift.max(normal.length, 1) { return false }
            i += 3
        }
        return true
    }
}
