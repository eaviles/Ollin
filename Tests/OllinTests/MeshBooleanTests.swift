import Foundation
import Ollin
import Testing

/// Pure-CPU checks on cutting one solid with another: the volumes obey the laws
/// a set operation has to obey, what comes out is still a printable solid, two
/// solids that miss each other leave each other alone, a solid against itself is
/// the hardest case there is (every face coincident), and the same two meshes
/// always give the same result. No GPU.
@Suite
struct MeshBooleanTests {

    /// A unit box moved off the origin, the everyday cutter.
    private func box(_ size: Double = 1, at offset: Vector3 = .zero) -> Mesh {
        Mesh.box(size: size).mapPositions { $0 + offset }
    }

    private func ball(radius: Double = 0.5, at offset: Vector3 = .zero) -> Mesh {
        Mesh.sphere(radius: radius, segments: 24, rings: 12).mapPositions { $0 + offset }
    }

    // MARK: - The laws

    @Test func twoHalfOverlappingBoxesGiveTheVolumesArithmeticSays() {
        let a = box()
        let b = box(at: Vector3(0.5, 0, 0))
        // The overlap is half of each box, so every answer is a round number.
        #expect(abs(a.union(b).volume - 1.5) < 1e-9)
        #expect(abs(a.intersection(b).volume - 0.5) < 1e-9)
        #expect(abs(a.subtracting(b).volume - 0.5) < 1e-9)
        #expect(abs(b.subtracting(a).volume - 0.5) < 1e-9)
        #expect(abs(a.symmetricDifference(b).volume - 1.0) < 1e-9)
    }

    @Test func theUnionAndTheOverlapAccountForBothSolids() {
        // |A| + |B| = |A or B| + |A and B|, whatever shape the two are.
        let a = box(1.4, at: Vector3(0.1, -0.2, 0.05))
        let b = ball(radius: 0.8, at: Vector3(0.6, 0.3, 0.2))
        let union = a.union(b).volume
        let overlap = a.intersection(b).volume
        #expect(overlap > 0.01, "the two solids were supposed to meet")
        #expect(abs(union + overlap - (a.volume + b.volume)) < a.volume * 1e-6)
    }

    @Test func cuttingAwayTheOverlapLeavesTheRest() {
        let a = box(1.2)
        let b = ball(radius: 0.7, at: Vector3(0.5, 0.4, 0))
        let cut = a.subtracting(b).volume
        let overlap = a.intersection(b).volume
        #expect(abs(cut + overlap - a.volume) < a.volume * 1e-6)
    }

    @Test func theSymmetricDifferenceIsBothSolidsWithoutTheOverlapTwice() {
        let a = box(1.1, at: Vector3(-0.2, 0, 0))
        let b = box(0.9, at: Vector3(0.3, 0.2, 0.1))
        let overlap = a.intersection(b).volume
        let either = a.symmetricDifference(b).volume
        #expect(overlap > 0.001)
        #expect(abs(either - (a.volume + b.volume - 2 * overlap)) < a.volume * 1e-6)
    }

    // MARK: - What comes out is still a solid

    @Test func everyOperationLeavesAPrintableSolid() {
        let a = box(1.3)
        let b = ball(radius: 0.75, at: Vector3(0.45, 0.35, 0.25))
        for (name, result) in [("union", a.union(b)),
                               ("intersection", a.intersection(b)),
                               ("difference", a.subtracting(b))] {
            let check = result.printCheck()
            #expect(check.isPrintable, "the \(name) came back as \(check.summary)")
        }
    }

    @Test func theSymmetricDifferenceClosesButMeetsItself() {
        // Both halves of it reach the curve where the two surfaces cross, and
        // they meet there: the solid touches itself along a line, which is a
        // real property of the shape rather than a torn surface. So the check
        // that matters is that nothing is open.
        let a = box(1.3)
        let b = ball(radius: 0.75, at: Vector3(0.45, 0.35, 0.25))
        let check = a.symmetricDifference(b).printCheck()
        #expect(check.boundaryEdgeCount == 0, "the symmetric difference tore: \(check.summary)")
        #expect(check.isConsistentlyOriented)
        #expect(!check.isInsideOut)
    }

    @Test func aDrilledHoleIsStillClosed() {
        // The classic: a bar with a shaft through it, which is the case where
        // the cutter's own surface has to survive facing inward.
        let bar = Mesh.box(width: 2, height: 0.5, depth: 0.5)
        let drill = Mesh.cylinder(radius: 0.15, height: 2, segments: 32)
        let drilled = bar.subtracting(drill)
        let check = drilled.printCheck()
        #expect(check.isPrintable, "the drilled bar came back as \(check.summary)")
        // A shaft the full height of the bar takes its own cylinder out of it.
        let shaft = Double.pi * 0.15 * 0.15 * 0.5
        #expect(abs(drilled.volume - (0.5 - shaft)) < 0.01)
    }

    // MARK: - Solids that miss, and solids that coincide

    @Test func solidsThatMissEachOtherLeaveEachOtherAlone() {
        let a = box()
        let far = box(at: Vector3(10, 0, 0))
        #expect(abs(a.union(far).volume - 2) < 1e-9)
        #expect(a.intersection(far).isEmpty || a.intersection(far).volume < 1e-12)
        #expect(abs(a.subtracting(far).volume - a.volume) < 1e-9)
    }

    @Test func aSolidAgainstItselfIsItself() {
        // Every face of one lies exactly in a face of the other, which is the
        // case a plane-thickness rule gets wrong first.
        let a = ball(radius: 0.6)
        #expect(abs(a.union(a).volume - a.volume) < a.volume * 1e-6)
        #expect(abs(a.intersection(a).volume - a.volume) < a.volume * 1e-6)
        #expect(a.subtracting(a).volume < a.volume * 1e-6)
    }

    @Test func twoBoxesSharingOneWallBecomeOneSolid() {
        // Touching but not overlapping: the shared wall must be dropped by one
        // side and kept by neither twice, or the result is two solids in a bag.
        let left = box()
        let right = box(at: Vector3(1, 0, 0))
        let joined = left.union(right)
        #expect(abs(joined.volume - 2) < 1e-9)
        let check = joined.printCheck()
        #expect(check.isPrintable, "the joined pair came back as \(check.summary)")
    }

    @Test func aSolidSwallowedWholeDisappears() {
        let outer = box(2)
        let inner = box(0.5)
        #expect(abs(outer.union(inner).volume - outer.volume) < 1e-9)
        #expect(abs(outer.intersection(inner).volume - inner.volume) < 1e-9)
        #expect(abs(outer.subtracting(inner).volume - (outer.volume - inner.volume)) < 1e-9)
        // A cavity with nothing reaching the outside is still a closed surface,
        // two shells deep.
        let hollow = outer.subtracting(inner).printCheck()
        #expect(hollow.isClosed)
        #expect(hollow.nonManifoldEdgeCount == 0)
    }

    // MARK: - Size, repeatability, and what rides along

    @Test func theCutWorksAtAnySize() {
        // The plane thickness is a fraction of the solids' own size, so the same
        // cut has to come out the same at a millimeter and at a kilometer.
        for scale in [0.001, 1.0, 1000.0] {
            let a = box(scale)
            let b = box(scale, at: Vector3(scale / 2, 0, 0))
            let expected = 1.5 * scale * scale * scale
            #expect(abs(a.union(b).volume - expected) < expected * 1e-6,
                    "the union went wrong at scale \(scale)")
        }
    }

    @Test func theSameTwoSolidsAlwaysGiveTheSameResult() {
        let a = box(1.3)
        let b = ball(radius: 0.7, at: Vector3(0.4, 0.2, 0.1))
        let once = a.subtracting(b)
        let again = a.subtracting(b)
        #expect(once.positions == again.positions)
        #expect(once.indices == again.indices)
        #expect(once.normals == again.normals)
    }

    @Test func textureCoordinatesAndColorsRideAlongWhenBothSidesHaveThem() {
        let a = Mesh.sphere(radius: 0.6, segments: 24, rings: 12)
        let b = Mesh.sphere(radius: 0.6, segments: 24, rings: 12).mapPositions { $0 + Vector3(0.5, 0, 0) }
        #expect(!a.uvs.isEmpty, "the generator was supposed to carry texture coordinates")
        let cut = a.subtracting(b)
        #expect(cut.uvs.count == cut.positions.count)
        #expect(cut.normals.count == cut.positions.count)

        // One side without them means the renderer would ignore a partial set,
        // so nothing comes through rather than half of it.
        let plain = Mesh(positions: b.positions, normals: b.normals, indices: b.indices)
        #expect(a.subtracting(plain).uvs.isEmpty)
    }

    @Test func aCutSurfaceKeepsTheSolidsOwnMaterial() {
        var a = Mesh.box(size: 1)
        a.material = MeshMaterial(baseColor: Color(red: 0.2, green: 0.4, blue: 0.9))
        let b = box(at: Vector3(0.5, 0, 0))
        #expect(a.subtracting(b).material?.baseColor == a.material?.baseColor)
        #expect(a.union(b).material?.baseColor == a.material?.baseColor)
    }

    @Test func normalsAtACutFaceTheWayTheCutDoes() {
        // The wall left by a cutter faces into the cavity, which is the sign
        // that tells a lit surface from an inside-out one.
        let bar = Mesh.box(width: 2, height: 0.6, depth: 0.6)
        let notch = Mesh.box(width: 0.4, height: 0.4, depth: 2)
        let cut = bar.subtracting(notch)
        #expect(cut.printCheck().isPrintable)
        #expect(!cut.printCheck().isInsideOut)
    }

    @Test func aStackOfCutsIsStillOneSolid() {
        // The carved block from the example: rounded by a ball, bored three
        // ways, bitten at every corner. Each cut goes into the result of the
        // last, which is where a defect in the surface compounds if there is one.
        let size = 2.0
        var block = Mesh.box(size: size)
            .intersection(Mesh.sphere(radius: size * 0.68, segments: 16, rings: 8))
        let shaft = Mesh.cylinder(radius: size * 0.22, height: size * 1.6, segments: 16)
        block = block.subtracting(shaft)
        block = block.subtracting(shaft.mapPositions { Vector3($0.y, -$0.x, $0.z) })
        block = block.subtracting(shaft.mapPositions { Vector3($0.x, $0.z, -$0.y) })
        let bite = Mesh.box(size: size * 0.3)
        for x in [-1.0, 1.0] {
            for y in [-1.0, 1.0] {
                for z in [-1.0, 1.0] {
                    block = block.subtracting(bite.mapPositions { $0 + Vector3(x, y, z) * (size / 2) })
                }
            }
        }
        let check = block.printCheck()
        #expect(check.isPrintable, "the carved block came back as \(check.summary)")
    }

    @Test func anEmptyMeshLeavesTheOtherAlone() {
        let a = box()
        let nothing = Mesh(positions: [], indices: [])
        #expect(a.union(nothing).volume == a.volume)
        #expect(a.subtracting(nothing).volume == a.volume)
        #expect(a.intersection(nothing).isEmpty)
        #expect(nothing.union(a).volume == a.volume)
        #expect(nothing.subtracting(a).isEmpty)
    }
}
