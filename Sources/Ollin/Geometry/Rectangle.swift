import Foundation

/// An axis-aligned rectangle in sketch points (top-left origin, y-down): a
/// `corner` (its top-left point) plus a `width` and `height`.
///
/// Like `Vector2`, `Rectangle` is a value you pass around and compose, not just
/// a draw call — it's the typed currency the `Drawer`'s `rect` takes, with the
/// bare scalar `drawRect(x, y, width, height)` as sugar over it.
public struct Rectangle: Equatable, Hashable, Sendable {
    /// Top-left corner (smallest x, smallest y).
    public let corner: Vector2
    public let width: Double
    public let height: Double

    public init(corner: Vector2, width: Double, height: Double) {
        self.corner = corner
        self.width = width
        self.height = height
    }

    /// Build from bare `x, y, width, height`.
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(corner: Vector2(x, y), width: width, height: height)
    }

    /// Build a rectangle centered on `center`.
    public init(center: Vector2, width: Double, height: Double) {
        self.init(corner: Vector2(center.x - width / 2, center.y - height / 2),
                  width: width, height: height)
    }

    /// Build the largest rectangle of `size`'s aspect ratio centered inside
    /// `container` — the letterboxed box to draw an image or video frame into
    /// without stretching it. A degenerate `size` or `container` yields
    /// `container` unchanged.
    public init(fitting size: Vector2, in container: Rectangle) {
        guard size.x > 0, size.y > 0, container.width > 0, container.height > 0 else {
            self = container
            return
        }
        let scale = Swift.min(container.width / size.x, container.height / size.y)
        self.init(center: container.center, width: size.x * scale, height: size.y * scale)
    }

    public var x: Double { corner.x }
    public var y: Double { corner.y }

    /// The center point.
    public var center: Vector2 { Vector2(corner.x + width / 2, corner.y + height / 2) }

    public var topLeft: Vector2 { corner }
    public var topRight: Vector2 { Vector2(corner.x + width, corner.y) }
    public var bottomRight: Vector2 { Vector2(corner.x + width, corner.y + height) }
    public var bottomLeft: Vector2 { Vector2(corner.x, corner.y + height) }

    /// Whether `point` lies inside the rectangle (the boundary counts as
    /// inside).
    public func contains(_ point: Vector2) -> Bool {
        point.x >= corner.x && point.x <= corner.x + width &&
        point.y >= corner.y && point.y <= corner.y + height
    }

    /// The point at normalized coordinates inside the rectangle: `u` runs 0…1
    /// left to right, `v` 0…1 top to bottom, so `point(u: 0.5, v: 0.5)` is the
    /// center. Values outside 0…1 land proportionally outside (not clamped).
    /// The canvas-wide form is `Sketch.uv(_:_:)`.
    public func point(u: Double, v: Double) -> Vector2 {
        Vector2(corner.x + u * width, corner.y + v * height)
    }

    /// The inverse of `point(u:v:)`: where `point` sits in the rectangle's
    /// normalized 0…1 space (`(0, 0)` at the top-left corner, `(1, 1)` at the
    /// bottom-right). A degenerate axis (zero width or height) reads 0.
    public func uv(of point: Vector2) -> Vector2 {
        Vector2(width > 0 ? (point.x - corner.x) / width : 0,
                height > 0 ? (point.y - corner.y) / height : 0)
    }
}

/// `points` uniformly scaled and centered to fill `frame` while keeping their
/// aspect: the "fit the points, not the transform" rule as a helper, so a
/// generated figure (a walk, an attractor, a chaos-game cloud) lands in a
/// frame without `scale()` fattening its strokes. A degenerate cloud (empty,
/// or all one point) comes back centered, unscaled.
public func fitted(_ points: [Vector2], in frame: Rectangle) -> [Vector2] {
    guard let first = points.first else { return [] }
    var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
    for point in points {
        minX = Swift.min(minX, point.x); maxX = Swift.max(maxX, point.x)
        minY = Swift.min(minY, point.y); maxY = Swift.max(maxY, point.y)
    }
    let spanX = maxX - minX, spanY = maxY - minY
    let scale = Swift.min(spanX > 0 ? frame.width / spanX : .infinity,
                          spanY > 0 ? frame.height / spanY : .infinity)
    let factor = scale.isFinite ? scale : 1
    let center = frame.center
    let midX = (minX + maxX) / 2, midY = (minY + maxY) / 2
    return points.map {
        Vector2(center.x + ($0.x - midX) * factor,
                center.y + ($0.y - midY) * factor)
    }
}
