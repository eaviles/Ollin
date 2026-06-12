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
}
