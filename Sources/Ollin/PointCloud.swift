import Foundation
import simd

/// A cloud of 3D points, drawn through a `Camera3D` as camera-facing disc splats
/// (see `Sketch.drawPointCloud`). Each point carries a world-space position, a
/// color, and a splat diameter in world units (perspective shrinks distant points).
///
/// Positions live in the camera's right-handed, y-up world space — *not* the 2D
/// canvas — so a cloud rides the camera rather than the transform stack. Build one
/// up front (a fixed scan) or rebuild it each frame (a live depth feed); a ~50k-point
/// cloud rebuilt per frame is comfortable.
public struct PointCloud: Sendable {

    /// One point: a world-space position, a color, and a splat diameter (world units).
    public struct Point: Sendable {
        public var position: Vector3
        public var color: Color
        public var size: Double

        public init(position: Vector3, color: Color = .white, size: Double = 1) {
            self.position = position
            self.color = color
            self.size = size
        }
    }

    /// The points, in draw order (a cloud composites by depth, so order is cosmetic).
    public var points: [Point]

    /// An empty cloud — `add` points to it, or assign `points`.
    public init(points: [Point] = []) { self.points = points }

    /// A cloud of `positions` sharing one `color` and splat `size`.
    public init(positions: [Vector3], color: Color = .white, size: Double = 1) {
        points = positions.map { Point(position: $0, color: color, size: size) }
    }

    /// A cloud of `positions` with matching per-point `colors` (paired up to the
    /// shorter of the two), sharing one splat `size`.
    public init(positions: [Vector3], colors: [Color], size: Double = 1) {
        points = zip(positions, colors).map { Point(position: $0, color: $1, size: size) }
    }

    /// Add one point to the cloud.
    public mutating func add(_ position: Vector3, color: Color = .white, size: Double = 1) {
        points.append(Point(position: position, color: color, size: size))
    }

    /// Remove every point, keeping the allocation — for rebuilding a live cloud
    /// each frame without re-growing the array.
    public mutating func removeAll() { points.removeAll(keepingCapacity: true) }

    public var count: Int { points.count }
    public var isEmpty: Bool { points.isEmpty }

    /// This cloud with every point's position run through `transform` (a 4×4
    /// matrix, applied as `transform · (x, y, z, 1)`), keeping each point's color
    /// and splat size.
    ///
    /// The use it's built for: placing a *camera-space* cloud into *world* space.
    /// A depth feed unprojects into the camera's own frame (`RGBDFrame.pointCloud`),
    /// and a depth source that also reports a 6DoF pose (the iPhone capture app's
    /// `latestPose`, a tethered depth device's pose) gives the camera→world transform — apply it
    /// and the cloud lands where it really is in the room, so clouds from different
    /// moments register against each other. `WorldCloud` fuses a sweep of them.
    ///
    /// The transform is assumed rigid (rotation + translation, as a camera pose is),
    /// so splat sizes pass through unscaled.
    public func transformed(by transform: simd_float4x4) -> PointCloud {
        var moved = self
        for index in moved.points.indices {
            moved.points[index].position = transform.transforming(moved.points[index].position)
        }
        return moved
    }
}

extension simd_float4x4 {
    /// Transform a point (`w = 1`, so translation applies) and drop back to `Vector3`.
    func transforming(_ p: Vector3) -> Vector3 {
        let v = self * SIMD4<Float>(Float(p.x), Float(p.y), Float(p.z), 1)
        return Vector3(Double(v.x), Double(v.y), Double(v.z))
    }
}
