import Foundation

/// A straight line in space, given as the point it starts at and the direction it
/// runs in, plus the tests that ask what it hits.
///
/// This is the value behind pointing at something: a wand held in the room, a
/// click carried into a scene, a sight line from a camera. The direction is kept
/// at length 1, so every distance a hit reports is a real distance in the same
/// units as the origin, and `point(at:)` reads as "this far along".
///
/// ```swift
/// let ray = Ray3(origin: eye, direction: target - eye)
/// if let distance = ray.hit(sphereAt: ball, radius: 0.2) {
///     withState {
///         translate(ray.point(at: distance))
///         drawSphere(radius: 0.02)
///     }
/// }
/// ```
///
/// A hit is only counted **in front of** the origin, so a body behind you never
/// answers. A ray built from a direction with no length hits nothing at all.
public struct Ray3: Equatable, Sendable {

    /// Where the line starts.
    public let origin: Vector3

    /// Which way it runs, at length 1. A direction with no length stays zero, and
    /// then nothing is ever hit. Constant, since the whole type rests on it being
    /// a unit vector: point a ray somewhere else by building another one.
    public let direction: Vector3

    /// Build a ray. `direction` is scaled to length 1, so it does not have to
    /// arrive that way: the difference of two points is enough.
    public init(origin: Vector3, direction: Vector3) {
        self.origin = origin
        self.direction = direction.normalized
    }

    /// The ray from `origin` toward `target`.
    public init(from origin: Vector3, toward target: Vector3) {
        self.init(origin: origin, direction: target - origin)
    }

    /// The point `distance` along the ray from its origin.
    public func point(at distance: Double) -> Vector3 { origin + direction * distance }

    /// How far `point` sits off the line, measured square to it. A point behind
    /// the origin is measured off the line the ray runs along, not off the origin.
    public func distance(to point: Vector3) -> Double {
        guard direction != .zero else { return origin.distance(to: point) }
        let along = (point - origin).dot(direction)
        return point.distance(to: origin + direction * along)
    }

    /// How far along the ray `point` sits. Negative means behind the origin.
    public func distanceAlong(_ point: Vector3) -> Double {
        (point - origin).dot(direction)
    }

    /// Where the ray first meets a ball, as a distance from the origin, or `nil`
    /// if it misses. A ray starting **inside** the ball reports the far side, so
    /// the answer is never behind you.
    public func hit(sphereAt center: Vector3, radius: Double) -> Double? {
        guard direction != .zero, radius > 0 else { return nil }
        // The standard quadratic, with the direction at length 1 so a == 1.
        let toCenter = origin - center
        let b = toCenter.dot(direction)
        let c = toCenter.lengthSquared - radius * radius
        let discriminant = b * b - c
        guard discriminant >= 0 else { return nil }
        let root = discriminant.squareRoot()
        let near = -b - root
        if near >= 0 { return near }
        let far = -b + root
        return far >= 0 ? far : nil
    }

    /// Where the ray first meets a box standing square to the world axes, as a
    /// distance from the origin, or `nil` if it misses. `size` is the whole width,
    /// height, and depth, so a box drawn with `drawBox(size:)` is tested with the
    /// same number.
    public func hit(boxAt center: Vector3, size: Vector3) -> Double? {
        guard direction != .zero else { return nil }
        // The slab test: clip the ray against each pair of faces in turn and keep
        // the overlap. A direction with a zero component runs parallel to that
        // pair, which the division answers as an infinite span, so a ray outside
        // the slab is thrown out by the comparison rather than by a special case.
        let half = Vector3(abs(size.x) / 2, abs(size.y) / 2, abs(size.z) / 2)
        var near = -Double.infinity
        var far = Double.infinity
        let o = [origin.x - center.x, origin.y - center.y, origin.z - center.z]
        let d = [direction.x, direction.y, direction.z]
        let h = [half.x, half.y, half.z]
        for axis in 0..<3 {
            if d[axis] == 0 {
                guard abs(o[axis]) <= h[axis] else { return nil }
                continue
            }
            let inverse = 1 / d[axis]
            var low = (-h[axis] - o[axis]) * inverse
            var high = (h[axis] - o[axis]) * inverse
            if low > high { swap(&low, &high) }
            near = max(near, low)
            far = min(far, high)
            guard near <= far else { return nil }
        }
        guard far >= 0 else { return nil }
        return near >= 0 ? near : far
    }

    /// Where the ray meets an endless flat surface through `point` facing
    /// `normal`, as a distance from the origin, or `nil` if it runs parallel to
    /// the surface or away from it.
    public func hit(planeAt point: Vector3, normal: Vector3) -> Double? {
        guard direction != .zero else { return nil }
        let facing = normal.normalized
        let slope = direction.dot(facing)
        guard abs(slope) > 1e-12 else { return nil }
        let distance = (point - origin).dot(facing) / slope
        return distance >= 0 ? distance : nil
    }
}
