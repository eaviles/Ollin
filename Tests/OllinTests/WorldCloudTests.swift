@testable import Ollin
import Testing
import simd

/// Pure CPU checks on `PointCloud.transformed(by:)` and the `WorldCloud` fusion
/// accumulator — the matrix placement and the voxel-grid dedup. No Metal device,
/// so these run everywhere including CI.
@Suite
struct WorldCloudTests {

    private func close(_ a: Vector3, _ b: Vector3, _ eps: Double = 1e-5) -> Bool {
        a.distance(to: b) <= eps
    }

    private func translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4<Float>(x, y, z, 1)
        return m
    }

    // MARK: PointCloud.transformed(by:)

    @Test func identityLeavesPointsUnchanged() {
        let cloud = PointCloud(positions: [Vector3(1, 2, 3), Vector3(-4, 5, -6)],
                               color: .red, size: 0.5)
        let moved = cloud.transformed(by: matrix_identity_float4x4)
        #expect(moved.count == 2)
        #expect(close(moved.points[0].position, Vector3(1, 2, 3)))
        #expect(close(moved.points[1].position, Vector3(-4, 5, -6)))
    }

    @Test func translationShiftsEveryPointAndKeepsColorAndSize() {
        let cloud = PointCloud(positions: [Vector3(0, 0, 0), Vector3(1, 1, 1)],
                               color: .blue, size: 0.25)
        let moved = cloud.transformed(by: translation(10, -2, 3))
        #expect(close(moved.points[0].position, Vector3(10, -2, 3)))
        #expect(close(moved.points[1].position, Vector3(11, -1, 4)))
        // A rigid pose leaves color and splat size untouched.
        #expect(moved.points[0].color == .blue)
        #expect(moved.points[0].size == 0.25)
    }

    @Test func rotationAboutZMapsXToY() {
        let cloud = PointCloud(positions: [Vector3(1, 0, 0)])
        let rot = simd_float4x4(simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 0, 1)))
        let moved = cloud.transformed(by: rot)
        #expect(close(moved.points[0].position, Vector3(0, 1, 0), 1e-4))
    }

    // MARK: WorldCloud fusion

    @Test func pointsInOneVoxelCollapseToTheLatest() {
        var world = WorldCloud(voxelSize: 0.1)
        // All three fall in voxel (0, 0, 0) — only the last survives.
        world.add(PointCloud(points: [PointCloud.Point(position: Vector3(0.01, 0, 0), color: .red)]))
        world.add(PointCloud(points: [PointCloud.Point(position: Vector3(0.02, 0, 0), color: .green)]))
        world.add(PointCloud(points: [PointCloud.Point(position: Vector3(0.03, 0, 0), color: .blue)]))
        #expect(world.count == 1)
        #expect(world.cloud.points[0].color == .blue)
        #expect(close(world.cloud.points[0].position, Vector3(0.03, 0, 0)))
    }

    @Test func separateVoxelsAccumulate() {
        var world = WorldCloud(voxelSize: 0.1)
        world.add(PointCloud(positions: [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)]))
        #expect(world.count == 3)
        // A fourth point in a fresh voxel adds; a fifth in an occupied one does not.
        world.add(PointCloud(positions: [Vector3(0, 0, 1), Vector3(1.04, 0, 0)]))
        #expect(world.count == 4)
    }

    @Test func reAddingTheSameFrameDoesNotGrow() {
        // A static pose re-observing the same surface is idempotent — the voxels
        // it touches are already filled, so the count holds steady.
        let frame = PointCloud(positions: (0..<200).map { Vector3(Double($0) * 0.05, 0, 0) })
        var world = WorldCloud(voxelSize: 0.1)
        world.add(frame)
        let after = world.count
        world.add(frame)
        world.add(frame)
        #expect(world.count == after)
    }

    @Test func transformedByMatchesTransformThenAdd() {
        let camera = PointCloud(positions: [Vector3(0, 0, -1), Vector3(0.5, 0.2, -2)],
                                color: .white, size: 0.01)
        let pose = translation(3, -1, 4)

        var a = WorldCloud(voxelSize: 0.001)
        a.add(camera, transformedBy: pose)
        var b = WorldCloud(voxelSize: 0.001)
        b.add(camera.transformed(by: pose))

        #expect(a.count == b.count)
        for (pa, pb) in zip(a.cloud.points, b.cloud.points) {
            #expect(close(pa.position, pb.position))
        }
        // And the fused points really are the world-space (translated) positions.
        #expect(close(a.cloud.points[0].position, Vector3(3, -1, 3)))
    }

    @Test func resetClears() {
        var world = WorldCloud(voxelSize: 0.1)
        world.add(PointCloud(positions: [Vector3(0, 0, 0), Vector3(1, 0, 0)]))
        #expect(!world.isEmpty)
        world.reset()
        #expect(world.isEmpty)
        #expect(world.count == 0)
        // It still fuses correctly after a reset (the grid was cleared, not left stale).
        world.add(PointCloud(positions: [Vector3(0, 0, 0)]))
        #expect(world.count == 1)
    }
}
