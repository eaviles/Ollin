import Foundation

/// One radius per corner of a rectangle, for `drawRect(_:cornerRadii:)` and
/// `SDF.rect(width:height:cornerRadii:)`: a tab rounded along its top, a
/// speech bubble with one square corner, a card whose corners differ. The
/// corners are named as they sit on the canvas, so `topLeft` is the corner
/// with the smallest `x` and `y`.
///
/// ```swift
/// drawRect(40, 40, 200, 60, cornerRadii: .top(20))              // a tab
/// drawRect(40, 40, 200, 60, cornerRadii: CornerRadii(topLeft: 30, topRight: 30,
///                                                      bottomRight: 30, bottomLeft: 0))
/// ```
///
/// A radius is clamped at draw time the way one `cornerRadius` is: two radii
/// that meet along a side are scaled down together until they fit it, so a
/// tab whose radii sum past its width keeps its shape and loses only size.
public struct CornerRadii: Equatable, Hashable, Sendable {
    public var topLeft: Double
    public var topRight: Double
    public var bottomRight: Double
    public var bottomLeft: Double

    public init(topLeft: Double, topRight: Double, bottomRight: Double, bottomLeft: Double) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    /// The same radius on every corner, what `cornerRadius:` draws.
    public init(_ radius: Double) {
        self.init(topLeft: radius, topRight: radius, bottomRight: radius, bottomLeft: radius)
    }

    /// No rounding on any corner.
    public static let zero = CornerRadii(0)

    /// The same radius on every corner.
    public static func all(_ radius: Double) -> CornerRadii { CornerRadii(radius) }
    /// The two top corners rounded, the bottom two square: a tab.
    public static func top(_ radius: Double) -> CornerRadii {
        CornerRadii(topLeft: radius, topRight: radius, bottomRight: 0, bottomLeft: 0)
    }
    /// The two bottom corners rounded, the top two square.
    public static func bottom(_ radius: Double) -> CornerRadii {
        CornerRadii(topLeft: 0, topRight: 0, bottomRight: radius, bottomLeft: radius)
    }
    /// The two left corners rounded, the right two square.
    public static func left(_ radius: Double) -> CornerRadii {
        CornerRadii(topLeft: radius, topRight: 0, bottomRight: 0, bottomLeft: radius)
    }
    /// The two right corners rounded, the left two square.
    public static func right(_ radius: Double) -> CornerRadii {
        CornerRadii(topLeft: 0, topRight: radius, bottomRight: radius, bottomLeft: 0)
    }

    /// The one radius every corner shares, or `nil` when they differ.
    public var uniformRadius: Double? {
        (topLeft == topRight && topRight == bottomRight && bottomRight == bottomLeft) ? topLeft : nil
    }

    /// The radii as they draw on a `width` by `height` rectangle: a negative
    /// radius reads as none, and where two radii on one side add up past it,
    /// all four scale down by the same factor, so the shape is kept and only
    /// its size gives (the rule stylesheets use for a box's corners). One
    /// radius on every corner reduces to the `cornerRadius:` clamp, half the
    /// shorter side.
    public func fitted(width: Double, height: Double) -> CornerRadii {
        let tl = max(0, topLeft), tr = max(0, topRight)
        let br = max(0, bottomRight), bl = max(0, bottomLeft)
        var factor = 1.0
        for (sum, side) in [(tl + tr, width), (bl + br, width), (tl + bl, height), (tr + br, height)]
        where sum > side && sum > 0 {
            factor = min(factor, side / sum)
        }
        return CornerRadii(topLeft: tl * factor, topRight: tr * factor,
                           bottomRight: br * factor, bottomLeft: bl * factor)
    }
}
