import Foundation

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
}
