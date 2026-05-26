import Foundation

/// An axis-aligned rectangle in sketch points (top-left origin, y-down): a
/// `corner` (its top-left point) plus a `width` and `height`.
///
/// Like `Vector2`, `Rectangle` is a value you pass around and compose, not just
/// a draw call — it's the typed currency the `Drawer`'s `rect` takes, with the
/// bare `rect(x:y:width:height:)` as p5-style sugar over it.
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

    /// Build from bare `x, y, width, height` (p5 argument order).
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(corner: Vector2(x, y), width: width, height: height)
    }

    /// Build a rectangle centered on `center` (p5's `rectMode(CENTER)`).
    public init(center: Vector2, width: Double, height: Double) {
        self.init(corner: Vector2(center.x - width / 2, center.y - height / 2),
                  width: width, height: height)
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
