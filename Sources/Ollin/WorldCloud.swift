import Foundation
import simd

/// Fuses a stream of point clouds — each a single moment seen from one camera pose —
/// into one cloud of the whole scene. Feed it a depth feed's per-frame cloud together
/// with that frame's camera→world transform and sweep the camera around: the room
/// builds up as a single cloud you can orbit and keep.
///
/// A live depth feed only ever sees the slice of the world in front of the lens, and
/// drawn alone each frame replaces the last. The missing piece is the camera's 6DoF
/// **pose** — where it was when it took the frame. A depth source that reports one
/// (the iPhone capture app's `latestPose`, a tethered depth device's pose) lets every
/// frame be placed in the same fixed world space, so the slices stack into a whole.
///
/// ```swift
/// var world = WorldCloud(voxelSize: 0.02)        // fuse at 2 cm
/// // each new frame, in draw():
/// if let frame = device.latestDepthFrame, let pose = device.latestPose {
///     world.add(frame.pointCloud(...), transformedBy: pose)
/// }
/// drawPointCloud(world.cloud)                     // the accumulated room
/// ```
///
/// Fusion is by a **voxel grid**: space is divided into cubes `voxelSize` on a side,
/// and the cloud keeps the most recent point seen in each cube. So re-observing a
/// surface refreshes it in place rather than piling up duplicates, and the cloud's
/// size is bounded by the scene's surface area, not the number of frames — a sweep
/// can run indefinitely. A smaller `voxelSize` keeps more detail and more points;
/// a larger one is coarser and lighter.
public struct WorldCloud {

    /// The fused cloud, in the depth feed's world space (meters) — pass it straight
    /// to `drawPointCloud`.
    public private(set) var cloud = PointCloud()

    /// The cube edge length (world units, meters for a depth feed) the scene is
    /// fused at — one kept point per occupied cube.
    public var voxelSize: Double

    /// Maps an occupied voxel to its point's index in `cloud.points`, so a repeat
    /// observation overwrites in place instead of appending.
    private var occupied: [Voxel: Int] = [:]

    /// Create an empty accumulator that fuses at `voxelSize` (meters).
    public init(voxelSize: Double = 0.02) {
        self.voxelSize = max(voxelSize, 1e-6)
    }

    /// Merge an **already world-space** cloud, keeping one point per voxel.
    public mutating func add(_ source: PointCloud) {
        cloud.points.reserveCapacity(cloud.points.count + source.points.count)
        for point in source.points { insert(point) }
    }

    /// Place a **camera-space** cloud into world space with `transform` (a camera→world
    /// pose) and merge it — `add(source.transformed(by: transform))`, but without
    /// building the intermediate cloud.
    public mutating func add(_ source: PointCloud, transformedBy transform: simd_float4x4) {
        cloud.points.reserveCapacity(cloud.points.count + source.points.count)
        for point in source.points {
            var moved = point
            moved.position = transform.transforming(point.position)
            insert(moved)
        }
    }

    /// Drop every fused point, keeping the allocation — start a fresh scan.
    public mutating func reset() {
        cloud.removeAll()
        occupied.removeAll(keepingCapacity: true)
    }

    /// The number of fused points (one per occupied voxel).
    public var count: Int { cloud.count }
    /// Whether anything has been fused yet.
    public var isEmpty: Bool { cloud.isEmpty }

    private mutating func insert(_ point: PointCloud.Point) {
        let key = Voxel(point.position, size: voxelSize)
        if let index = occupied[key] {
            cloud.points[index] = point     // refresh the cube's point in place
        } else {
            occupied[key] = cloud.points.count
            cloud.points.append(point)
        }
    }

    /// An integer voxel coordinate — a position quantized to the fusion grid.
    private struct Voxel: Hashable {
        let x: Int, y: Int, z: Int
        init(_ p: Vector3, size: Double) {
            x = Int((p.x / size).rounded(.down))
            y = Int((p.y / size).rounded(.down))
            z = Int((p.z / size).rounded(.down))
        }
    }
}
