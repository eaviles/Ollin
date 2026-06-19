import Foundation

/// A circle in sketch points (top-left origin, y-down): a `center` and a
/// `radius`.
///
/// Like `Vector2` and `Rectangle`, `Circle` is a value you pass around and
/// compose, not just a draw call — it's the typed currency `drawCircle(_:)` and
/// the batch `drawCircles(_:)` take, with the bare scalar
/// `drawCircle(x, y, radius)` as sugar over it.
public struct Circle: Equatable, Hashable, Sendable {
    public let center: Vector2
    public let radius: Double

    public init(center: Vector2, radius: Double) {
        self.center = center
        self.radius = radius
    }

    /// Build from bare `x, y, radius`.
    public init(x: Double, y: Double, radius: Double) {
        self.init(center: Vector2(x, y), radius: radius)
    }

    public var x: Double { center.x }
    public var y: Double { center.y }

    /// The diameter (`radius * 2`).
    public var diameter: Double { radius * 2 }

    /// The axis-aligned bounding box.
    public var bounds: Rectangle {
        Rectangle(center: center, width: diameter, height: diameter)
    }

    /// Whether `point` lies inside the circle (the boundary counts as inside).
    public func contains(_ point: Vector2) -> Bool {
        let dx = point.x - center.x, dy = point.y - center.y
        return dx * dx + dy * dy <= radius * radius
    }
}
