import Foundation
import simd

/// A flat surface in space with two directions of its own, so that a place on
/// it is two numbers: a wall, a floor, a table top, a sheet held anywhere.
///
/// The surface has an `origin`, a `right` and an `up` that lie in it, and a
/// `normal` that points out of its front. Its own coordinates are in the units
/// of the space it stands in (meters, for a room a phone measured): `x` runs
/// along `right`, `y` along `up`, and a third number lifts a point off the
/// front along `normal`.
///
/// ```swift
/// let wall = Plane3(origin: Vector3(0, 1.5, -2), normal: .unitZ)
/// let spot = wall.point(at: Vector2(0.4, 0.2))        // 40 cm right, 20 cm up
/// if let ray = cameraRay(through: mouse),
///    let clicked = wall.intersection(with: ray) {
///     pins.append(clicked)                            // a point that stays on the wall
/// }
/// ```
///
/// `withPlane(_:)` draws in these coordinates, and `Ray3.hit(_:)` asks where a
/// line meets the surface. The surface has no edges: it runs on in every
/// direction, and what is drawn on it decides how much of it shows.
public struct Plane3: Equatable, Sendable {

    /// The point of the surface its own coordinates count from.
    public let origin: Vector3

    /// The surface's own x direction, at length 1, lying in the surface.
    public let right: Vector3

    /// The surface's own y direction, at length 1, lying in the surface and
    /// square to `right`.
    public let up: Vector3

    /// The way the surface faces, at length 1: out of its front, square to
    /// both `right` and `up`.
    public var normal: Vector3 { right.cross(up) }

    /// A surface through `origin` facing along `normal`, with `up` saying
    /// which way should read as up on it.
    ///
    /// `up` does not have to lie in the surface. Its part along the surface is
    /// what is kept, so the room's own up (the default) gives a wall whose `y`
    /// climbs it and whose `x` runs to the right of someone facing it. A floor
    /// or a ceiling faces along the room's up, which leaves nothing to keep,
    /// and takes -z for its `up` (so `x` is still the room's x). A `normal`
    /// with no length faces +z.
    public init(origin: Vector3, normal: Vector3, up: Vector3 = .unitY) {
        let facing = normal.lengthSquared > 1e-24 ? normal.normalized : Vector3.unitZ
        var along = up - facing * up.dot(facing)
        if along.lengthSquared < 1e-12 {
            // The hint runs along the normal. Take the next direction that
            // cannot: -z for a surface facing up or down, the room's up for
            // every other.
            let fallback = abs(facing.y) > 0.9 ? Vector3(0, 0, -1) : Vector3.unitY
            along = fallback - facing * fallback.dot(facing)
        }
        let upAxis = along.normalized
        self.origin = origin
        self.up = upAxis
        self.right = upAxis.cross(facing).normalized
    }

    /// A surface through `origin` whose x runs along `right` and whose y runs
    /// as near to `up` as a direction square to `right` can. The two are
    /// brought to length 1 and made square, `right` kept as given. Returns
    /// `nil` when the two run along one line, which names no surface.
    public init?(origin: Vector3, right: Vector3, up: Vector3) {
        guard right.lengthSquared > 1e-24 else { return nil }
        let x = right.normalized
        let along = up - x * up.dot(x)
        guard along.lengthSquared > 1e-18 else { return nil }
        self.origin = origin
        self.right = x
        self.up = along.normalized
    }

    /// The surface that lies nearest to `points`: through their middle, turned
    /// so the squared distances from the points to it add up to the least they
    /// can. Three points give the surface through all three, and more give the
    /// best one, which is how a wall is found from a handful of measured
    /// places on it.
    ///
    /// The fit alone cannot say which side is the front. With `facing` the
    /// front is the side that point is on (hand it where the camera stood).
    /// Without it the front is the side from which the points, taken in the
    /// order given, run counter-clockwise. `up` reads as in
    /// `init(origin:normal:up:)`.
    ///
    /// Returns `nil` for fewer than three points, or points along one line.
    public init?(through points: [Vector3], facing: Vector3? = nil, up: Vector3 = .unitY) {
        guard points.count >= 3 else { return nil }
        var middle = Vector3.zero
        for point in points { middle += point }
        middle = middle / Double(points.count)

        // The scatter of the points about their middle. The direction it is
        // thinnest in is the surface's normal.
        var xx = 0.0, xy = 0.0, xz = 0.0, yy = 0.0, yz = 0.0, zz = 0.0
        for point in points {
            let d = point - middle
            xx += d.x * d.x; xy += d.x * d.y; xz += d.x * d.z
            yy += d.y * d.y; yz += d.y * d.z; zz += d.z * d.z
        }
        let scale = xx + yy + zz
        guard scale > 1e-24 else { return nil }
        guard var normal = Plane3.thinnestDirection(xx / scale, xy / scale, xz / scale,
                                                    yy / scale, yz / scale, zz / scale) else {
            return nil
        }

        if let facing {
            if (facing - middle).dot(normal) < 0 { normal = -normal }
        } else {
            // The points' own turn, added up the way a polygon's area is: it
            // points out of the side they run counter-clockwise on.
            var turn = Vector3.zero
            for i in points.indices {
                let a = points[i] - middle, b = points[(i + 1) % points.count] - middle
                turn += a.cross(b)
            }
            if turn.dot(normal) < 0 { normal = -normal }
        }
        self.init(origin: middle, normal: normal, up: up)
    }

    /// The unit direction a symmetric scatter matrix is thinnest in, or `nil`
    /// when it is thin in more than one (points along a line, or all in one
    /// place). The matrix arrives scaled so its diagonal adds up to 1.
    private static func thinnestDirection(_ xx: Double, _ xy: Double, _ xz: Double,
                                          _ yy: Double, _ yz: Double, _ zz: Double) -> Vector3? {
        // The three eigenvalues of a symmetric 3 by 3 matrix in closed form
        // (the trigonometric solution of its characteristic cubic).
        let mean = (xx + yy + zz) / 3
        let off = xy * xy + xz * xz + yz * yz
        let spread = (xx - mean) * (xx - mean) + (yy - mean) * (yy - mean)
            + (zz - mean) * (zz - mean) + 2 * off
        guard spread > 1e-30 else { return nil }      // the same in every direction
        let p = (spread / 6).squareRoot()
        let bxx = (xx - mean) / p, byy = (yy - mean) / p, bzz = (zz - mean) / p
        let bxy = xy / p, bxz = xz / p, byz = yz / p
        let half = (bxx * (byy * bzz - byz * byz) - bxy * (bxy * bzz - byz * bxz)
            + bxz * (bxy * byz - byy * bxz)) / 2
        let angle = acos(min(1, max(-1, half))) / 3
        let largest = mean + 2 * p * cos(angle)
        let smallest = mean + 2 * p * cos(angle + 2 * .pi / 3)
        let middle = 3 * mean - largest - smallest
        // A surface needs two directions with real spread. Points along a line
        // leave the middle value at nothing beside the largest: under a
        // millionth of it, which is a strip a thousand times longer than it is
        // wide (and well above what the closed form's own rounding leaves, a
        // few parts in a billion).
        guard middle > 1e-6 * largest else { return nil }

        // With the smallest value taken off the diagonal, every row of the
        // matrix lies square to the direction sought, so the cross product of
        // two rows runs along it. The longest of the three is the steadiest.
        let r0 = Vector3(xx - smallest, xy, xz)
        let r1 = Vector3(xy, yy - smallest, yz)
        let r2 = Vector3(xz, yz, zz - smallest)
        let candidates = [r0.cross(r1), r0.cross(r2), r1.cross(r2)]
        guard let best = candidates.max(by: { $0.lengthSquared < $1.lengthSquared }),
              best.lengthSquared > 1e-30 else { return nil }
        return best.normalized
    }

    // MARK: Places on it

    /// The point of space at the surface's own `coordinates`, lifted `lift`
    /// off its front (0, the default, is on the surface).
    public func point(at coordinates: Vector2, lift: Double = 0) -> Vector3 {
        origin + right * coordinates.x + up * coordinates.y + normal * lift
    }

    /// Where `point` falls on the surface, in the surface's own coordinates:
    /// the place straight under it, whatever its distance off the surface.
    public func coordinates(of point: Vector3) -> Vector2 {
        let d = point - origin
        return Vector2(d.dot(right), d.dot(up))
    }

    /// How far `point` stands off the surface: positive in front of it,
    /// negative behind, 0 on it.
    public func distance(to point: Vector3) -> Double {
        (point - origin).dot(normal)
    }

    /// Where `ray` meets the surface, or `nil` when it runs along the surface
    /// or away from it. Either side counts: a ray from behind meets the back.
    ///
    /// ```swift
    /// if let ray = cameraRay(through: mouse), let spot = wall.intersection(with: ray) {
    ///     let onWall = wall.coordinates(of: spot)     // the same place as two numbers
    /// }
    /// ```
    public func intersection(with ray: Ray3) -> Vector3? {
        ray.hit(self).map(ray.point(at:))
    }

    // MARK: Other surfaces from this one

    /// The same surface with its coordinates counted from another of its
    /// points: `offset` away, in its own coordinates, and `lift` off its front.
    public func moved(by offset: Vector2, lift: Double = 0) -> Plane3 {
        Plane3(origin: point(at: offset, lift: lift), right: right, up: up) ?? self
    }

    /// The same surface with its two directions turned by `angle` radians,
    /// counter-clockwise for someone facing its front.
    public func turned(by angle: Double) -> Plane3 {
        let c = cos(angle), s = sin(angle)
        return Plane3(origin: origin, right: right * c + up * s, up: up * c - right * s) ?? self
    }

    /// The same surface seen from behind: its normal turned around and its
    /// `right` with it, so `up` still reads as up.
    public var flipped: Plane3 {
        Plane3(origin: origin, right: -right, up: up) ?? self
    }

    /// The matrix that carries the surface's own coordinates into space: x
    /// along `right`, y along `up`, z along `normal`, with (0, 0, 0) at
    /// `origin`. `withPlane(_:)` is this handed to `transform(_:)`.
    public var matrix: simd_float4x4 {
        let n = normal
        return simd_float4x4(columns: (
            SIMD4<Float>(Float(right.x), Float(right.y), Float(right.z), 0),
            SIMD4<Float>(Float(up.x), Float(up.y), Float(up.z), 0),
            SIMD4<Float>(Float(n.x), Float(n.y), Float(n.z), 0),
            SIMD4<Float>(Float(origin.x), Float(origin.y), Float(origin.z), 1)
        ))
    }
}

public extension Ray3 {

    /// Where the ray meets a flat surface, as a distance from the origin, or
    /// `nil` if it runs along the surface or away from it. `Plane3` has the
    /// same question answered as a point: `intersection(with:)`.
    func hit(_ plane: Plane3) -> Double? {
        hit(planeAt: plane.origin, normal: plane.normal)
    }
}
