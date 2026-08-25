import Foundation
import simd

/// A cloud of 3D points, drawn through a `Camera3D` as camera-facing disc splats
/// (see `Sketch.drawPointCloud`). Each point carries a world-space position, a
/// color, and a splat diameter in world units (perspective shrinks distant points).
///
/// Positions live in the camera's right-handed, y-up world space, *not* the 2D
/// canvas, so a cloud rides the camera rather than the transform stack. Build one
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

    /// An empty cloud. `add` points to it, or assign `points`.
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

    /// Remove every point, keeping the allocation, for rebuilding a live cloud
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
    /// `latestPose`, a tethered depth device's pose) gives the camera→world transform. Apply it
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

public extension PointCloud {
    /// The mean of the cloud's positions, or `nil` for an empty cloud. The
    /// point a camera frames to look at the cloud as a whole.
    var centroid: Vector3? {
        guard !points.isEmpty else { return nil }
        var sum = Vector3.zero
        for p in points { sum += p.position }
        return sum / Double(points.count)
    }

    /// How spread out the cloud is around its centroid: the root of the mean
    /// squared distance, in the cloud's own units. `0` for an empty cloud.
    /// With `centroid`, the two numbers a framing camera wants; an orbit
    /// radius of a few times this keeps the whole cloud comfortably in view.
    /// Depth feeds flicker a little frame to frame, so ease an orbit toward
    /// these rather than snapping to them.
    var spreadRadius: Double {
        guard let center = centroid else { return 0 }
        var sum = 0.0
        for p in points { sum += p.position.distanceSquared(to: center) }
        return (sum / Double(points.count)).squareRoot()
    }
}

extension Vector3 {
    /// This point moved by a 4×4 transform, with `w = 1` so the translation applies.
    ///
    /// The pair to `PointCloud.transformed(by:)`, for the single points around a cloud:
    /// where a depth camera is standing, where a fused scan's drift `correction` puts
    /// something the camera reported, where a scene node sits.
    public func transformed(by transform: simd_float4x4) -> Vector3 {
        transform.transforming(self)
    }
}

extension simd_float4x4 {
    /// Transform a point (`w = 1`, so translation applies) and drop back to `Vector3`.
    func transforming(_ p: Vector3) -> Vector3 {
        let v = self * SIMD4<Float>(Float(p.x), Float(p.y), Float(p.z), 1)
        return Vector3(Double(v.x), Double(v.y), Double(v.z))
    }
}
