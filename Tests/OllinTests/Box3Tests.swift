import Testing
@testable import Ollin

/// Pure checks on `Box3`, the axis-aligned box that `Mesh.bounds`,
/// `Scene.bounds`, and the marched fields speak.
struct Box3Tests {

    @Test func centerAndSizeReadOffTheCorners() {
        let box = Box3(min: Vector3(-1, 2, -3), max: Vector3(3, 4, 5))
        #expect(box.center == Vector3(1, 3, 1))
        #expect(box.size == Vector3(4, 2, 8))
        #expect(box.longestSide == 8)
        #expect(!box.isEmpty)
    }

    @Test func centerAndSizeBuildTheSameBox() {
        let box = Box3(center: Vector3(1, 3, 1), size: Vector3(4, 2, 8))
        #expect(box == Box3(min: Vector3(-1, 2, -3), max: Vector3(3, 4, 5)))
    }

    @Test func containingPointsFindsTheirBox() {
        let points = [Vector3(0, 0, 0), Vector3(2, -1, 5), Vector3(-3, 4, 1)]
        #expect(Box3(containing: points) == Box3(min: Vector3(-3, -1, 0), max: Vector3(2, 4, 5)))
        #expect(Box3(containing: []) == nil, "no points, no box")
        #expect(Box3(containing: [Vector3(1, 2, 3)]) == Box3(min: Vector3(1, 2, 3), max: Vector3(1, 2, 3)))
    }

    @Test func zeroAndFlatBoxesAreEmpty() {
        #expect(Box3.zero.isEmpty)
        #expect(Box3.zero.center == .zero)
        #expect(Box3(min: Vector3(1, 2, 3), max: Vector3(1, 2, 3)).isEmpty, "a point has no volume")
        #expect(Box3(min: Vector3(0, 0, 0), max: Vector3(1, 0, 1)).isEmpty, "a flat slab has no volume")
    }

    @Test func containsCountsTheFaces() {
        let box = Box3(min: Vector3(0, 0, 0), max: Vector3(2, 2, 2))
        #expect(box.contains(Vector3(1, 1, 1)))
        #expect(box.contains(Vector3(0, 2, 1)), "a face is inside")
        #expect(!box.contains(Vector3(1, 1, 2.001)))
        #expect(!box.contains(Vector3(-0.001, 1, 1)))
    }

    @Test func paddingGrowsEverySide() {
        let box = Box3(min: Vector3(0, 0, 0), max: Vector3(2, 2, 2))
        let grown = box.padded(by: 0.5)
        #expect(grown == Box3(min: Vector3(-0.5, -0.5, -0.5), max: Vector3(2.5, 2.5, 2.5)))
        #expect(grown.center == box.center, "padding keeps the center")
        #expect(grown.padded(by: -0.5) == box, "a negative amount shrinks it back")
    }

    @Test func unionHoldsBoth() {
        let a = Box3(min: Vector3(0, 0, 0), max: Vector3(1, 1, 1))
        let b = Box3(min: Vector3(-2, 0.5, 3), max: Vector3(0.5, 4, 5))
        let both = a.union(b)
        #expect(both == Box3(min: Vector3(-2, 0, 0), max: Vector3(1, 4, 5)))
        #expect(both == b.union(a), "order does not matter")
        #expect(a.union(a) == a)
    }

    @Test func aMeshReportsItsBoxAndAnEmptyOneReportsZero() {
        let mesh = Mesh(positions: [Vector3(-1, 0, 2), Vector3(3, -2, 0), Vector3(0, 1, 1)], indices: [0, 1, 2])
        #expect(mesh.bounds == Box3(min: Vector3(-1, -2, 0), max: Vector3(3, 1, 2)))
        #expect(mesh.center == mesh.bounds.center)
        #expect(mesh.size == mesh.bounds.size)
        #expect(Mesh(positions: [], indices: []).bounds == .zero)
    }
}
