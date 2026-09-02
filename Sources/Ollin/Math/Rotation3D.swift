import Foundation
import simd

/// A turn in space, as one value: how far, about which axis.
///
/// Everything that faces somewhere in three dimensions carries one of these: a
/// body in a `World3D`, a wheel on a vehicle, the pose a mesh is drawn in. It
/// reads as an angle about an axis, and underneath it is a unit quaternion,
/// which is what lets two turns compose without the trouble three separate
/// angles run into.
///
/// ```swift
/// let tilt = Rotation3D(angle: .pi / 6, axis: .unitZ)
/// body.rotation = tilt * .aboutY(time)       // spin about y, then tilt
/// rotate(body.rotation)                      // the same pose, while drawing
/// let up = Vector3.unitY.rotated(by: tilt)   // where "up" points now
/// ```
///
/// `a * b` turns by `b` first and then by `a`, the way matrices multiply, so a
/// chain reads right to left. The turn that takes one direction to another
/// (`Rotation3D(from:to:)`) and the turn part of the way toward another
/// (`interpolated(to:_:)`) are here because they are what a sketch reaches for
/// when it points something at something else.
public struct Rotation3D: Equatable, Hashable, Sendable, Codable {

    /// The quaternion's parts, at unit length, with `w` never negative: a
    /// quaternion and its negation are the same turn, and keeping one form
    /// is what lets two equal turns compare equal.
    public let x: Double
    public let y: Double
    public let z: Double
    public let w: Double

    /// No turn at all.
    public static let identity = Rotation3D(x: 0, y: 0, z: 0, w: 1)

    /// A turn from its quaternion parts, for a value that arrives that way (a
    /// file's node, a solver's body). Scaled to unit length; four zeros give the
    /// identity.
    public init(x: Double, y: Double, z: Double, w: Double) {
        let length = (x * x + y * y + z * z + w * w).squareRoot()
        guard length > 1e-12 else {
            self.x = 0; self.y = 0; self.z = 0; self.w = 1
            return
        }
        // One form per turn: `w` non-negative, and for a half turn (`w` zero)
        // the first non-zero part positive.
        var sign = 1.0
        if w < 0 || (w == 0 && (x < 0 || (x == 0 && (y < 0 || (y == 0 && z < 0))))) {
            sign = -1
        }
        self.x = sign * x / length
        self.y = sign * y / length
        self.z = sign * z / length
        self.w = sign * w / length
    }

    /// The turn of `angle` radians about `axis`, right-handed: counter-clockwise
    /// looking from the positive axis toward the origin, the same sense
    /// `rotate(_:axis:)` draws in. An axis with no length gives no turn.
    public init(angle: Double, axis: Vector3) {
        let unit = axis.normalized
        guard unit.lengthSquared > 0 else {
            self = .identity
            return
        }
        let half = angle / 2
        let s = sin(half)
        self.init(x: unit.x * s, y: unit.y * s, z: unit.z * s, w: cos(half))
    }

    /// The shortest turn that takes the direction `from` to the direction `to`.
    ///
    /// Neither has to be unit length. Two directions already aligned give no
    /// turn; two directly opposed give a half turn about an axis square to
    /// them, since any such axis does.
    public init(from: Vector3, to: Vector3) {
        let a = from.normalized, b = to.normalized
        guard a.lengthSquared > 0, b.lengthSquared > 0 else {
            self = .identity
            return
        }
        let dot = a.dot(b)
        if dot < -1 + 1e-9 {
            // Opposed: pick the axis least aligned with `a` and turn about
            // the perpendicular that leaves.
            let pick = abs(a.x) < 0.9 ? Vector3.unitX : Vector3.unitY
            let axis = a.cross(pick).normalized
            self.init(x: axis.x, y: axis.y, z: axis.z, w: 0)
            return
        }
        let axis = a.cross(b)
        self.init(x: axis.x, y: axis.y, z: axis.z, w: 1 + dot)
    }

    /// A turn about the x-axis.
    public static func aboutX(_ radians: Double) -> Rotation3D {
        Rotation3D(angle: radians, axis: .unitX)
    }
    /// A turn about the y-axis.
    public static func aboutY(_ radians: Double) -> Rotation3D {
        Rotation3D(angle: radians, axis: .unitY)
    }
    /// A turn about the z-axis.
    public static func aboutZ(_ radians: Double) -> Rotation3D {
        Rotation3D(angle: radians, axis: .unitZ)
    }

    /// How far the turn goes, in radians, `0...π`. Read it with `axis`.
    public var angle: Double {
        2 * acos(max(-1, min(1, w)))
    }

    /// The axis the turn is about, at unit length; `unitY` for no turn at all,
    /// which has no axis of its own.
    public var axis: Vector3 {
        let s = (1 - w * w).squareRoot()
        guard s > 1e-9 else { return .unitY }
        return Vector3(x / s, y / s, z / s)
    }

    /// The turn that undoes this one.
    public var inverse: Rotation3D {
        Rotation3D(x: -x, y: -y, z: -z, w: w)
    }

    /// One turn after another: `a * b` turns by `b` first, then by `a`.
    public static func * (a: Rotation3D, b: Rotation3D) -> Rotation3D {
        Rotation3D(
            x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
            y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
            z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
            w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z)
    }

    /// The turn `t` of the way from this one to `other`, along the shortest
    /// arc (`0` is this turn, `1` is `other`), at a steady rate in between.
    public func interpolated(to other: Rotation3D, _ t: Double) -> Rotation3D {
        var bx = other.x, by = other.y, bz = other.z, bw = other.w
        var cosine = x * bx + y * by + z * bz + w * bw
        // The two forms of `other` are the same turn; take the one on this
        // side of the sphere so the arc is the short one.
        if cosine < 0 {
            cosine = -cosine
            bx = -bx; by = -by; bz = -bz; bw = -bw
        }
        let s0: Double, s1: Double
        if cosine > 1 - 1e-9 {
            // Nearly the same turn: a straight blend is the arc to within
            // rounding, and the sine below would divide by nothing.
            s0 = 1 - t
            s1 = t
        } else {
            let theta = acos(cosine)
            let sine = sin(theta)
            s0 = sin((1 - t) * theta) / sine
            s1 = sin(t * theta) / sine
        }
        return Rotation3D(x: s0 * x + s1 * bx, y: s0 * y + s1 * by,
                          z: s0 * z + s1 * bz, w: s0 * w + s1 * bw)
    }

    /// The turn as the 4×4 matrix the drawing stack composes, for a transform
    /// built by hand (`transform(_:)`).
    public var matrix: simd_float4x4 {
        simd_float4x4(simd_quatf(ix: Float(x), iy: Float(y), iz: Float(z), r: Float(w)))
    }
}

public extension Vector3 {
    /// This vector turned by `rotation`.
    func rotated(by rotation: Rotation3D) -> Vector3 {
        // q · v · q⁻¹, written out: t = 2 (q.xyz × v); v + w t + q.xyz × t.
        let qx = rotation.x, qy = rotation.y, qz = rotation.z, qw = rotation.w
        let tx = 2 * (qy * z - qz * y)
        let ty = 2 * (qz * x - qx * z)
        let tz = 2 * (qx * y - qy * x)
        return Vector3(x + qw * tx + (qy * tz - qz * ty),
                       y + qw * ty + (qz * tx - qx * tz),
                       z + qw * tz + (qx * ty - qy * tx))
    }
}
