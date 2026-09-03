import Foundation

/// An axis-aligned box in space: a `min` corner and a `max` corner, the
/// smallest and largest coordinate on every axis.
///
/// The bounds of a mesh or a scene, the reach of a metaball field, the region
/// a surface is marched over. Like `Rectangle` on the canvas, it is a value you
/// pass around and compose, not a draw call: `center` and `size` are read off
/// it, `padded(by:)` grows it, `union(_:)` folds two together, and
/// `init(containing:)` finds the box around a cloud of points.
public struct Box3: Equatable, Hashable, Sendable, Codable {
    /// The corner with the smallest coordinate on every axis.
    public var min: Vector3
    /// The corner with the largest coordinate on every axis.
    public var max: Vector3

    public init(min: Vector3, max: Vector3) {
        self.min = min
        self.max = max
    }

    /// A box of `size` centered on `center`.
    public init(center: Vector3, size: Vector3) {
        let half = size * 0.5
        self.init(min: center - half, max: center + half)
    }

    /// The box around `points`, or `nil` when there are none.
    public init?(containing points: [Vector3]) {
        guard let first = points.first else { return nil }
        var lo = first, hi = first
        for p in points {
            lo = Vector3(Swift.min(lo.x, p.x), Swift.min(lo.y, p.y), Swift.min(lo.z, p.z))
            hi = Vector3(Swift.max(hi.x, p.x), Swift.max(hi.y, p.y), Swift.max(hi.z, p.z))
        }
        self.init(min: lo, max: hi)
    }

    /// The empty box at the origin, what a mesh or a scene with no geometry reports.
    public static let zero = Box3(min: .zero, max: .zero)

    /// The middle of the box.
    public var center: Vector3 { (min + max) * 0.5 }

    /// The full extent: width (x), height (y), and depth (z) as one `Vector3`.
    public var size: Vector3 { max - min }

    /// The longest of the three sides.
    public var longestSide: Double { Swift.max(size.x, Swift.max(size.y, size.z)) }

    /// Whether the box encloses no volume: a side of zero or negative length.
    public var isEmpty: Bool { size.x <= 0 || size.y <= 0 || size.z <= 0 }

    /// Whether `point` lies inside the box (the faces count as inside).
    public func contains(_ point: Vector3) -> Bool {
        point.x >= min.x && point.x <= max.x &&
        point.y >= min.y && point.y <= max.y &&
        point.z >= min.z && point.z <= max.z
    }

    /// The box grown by `amount` on every side, so its size grows by twice
    /// that on each axis. A negative amount shrinks it.
    public func padded(by amount: Double) -> Box3 {
        let pad = Vector3(amount, amount, amount)
        return Box3(min: min - pad, max: max + pad)
    }

    /// The smallest box holding both this one and `other`.
    public func union(_ other: Box3) -> Box3 {
        Box3(min: Vector3(Swift.min(min.x, other.min.x), Swift.min(min.y, other.min.y), Swift.min(min.z, other.min.z)),
             max: Vector3(Swift.max(max.x, other.max.x), Swift.max(max.y, other.max.y), Swift.max(max.z, other.max.z)))
    }
}
