import Foundation
import Ollin

/// The spline data a `.path` joint is built from: one position, one tangent,
/// and one normal per point, flattened into the nine-floats-per-point buffer
/// the bridge reads.
///
/// A sketch hands over bare points, because that is what a track looks like
/// when you draw it. The curve through them is a cardinal spline (each point's
/// tangent is half the span between its neighbors), and the normals are
/// carried along the curve by parallel transport, which is what keeps a frame
/// from spinning about the track for no reason. One consequence worth knowing:
/// on a closed loop the frame that comes back around need not match the one it
/// set out with, so a `.followsPath` rider can find a twist at the seam.
struct PathSpline {
    /// Nine floats per point: position, then tangent, then normal.
    private(set) var floats: [Float] = []
    private(set) var count = 0

    /// Build the spline through `points`, in meters. `scale` divides world
    /// units into the meters the solver works in, and applies to the tangents
    /// too, since a Hermite tangent is a derivative and has to shrink with the
    /// curve it belongs to.
    init?(through points: [Vector3], looping: Bool, scale: Double) {
        // Repeated points make a zero tangent, and a looping path whose last
        // point is its first is the same point twice over.
        var knots: [Vector3] = []
        for point in points where knots.last.map({ $0.distanceSquared(to: point) > 1e-12 }) ?? true {
            knots.append(point)
        }
        if looping, knots.count > 1,
           knots[0].distanceSquared(to: knots[knots.count - 1]) <= 1e-12 {
            knots.removeLast()
        }
        guard knots.count >= 2 else { return nil }

        let n = knots.count
        var tangents: [Vector3] = []
        tangents.reserveCapacity(n)
        for i in 0 ..< n {
            if looping {
                tangents.append((knots[(i + 1) % n] - knots[(i + n - 1) % n]) * 0.5)
            } else if i == 0 {
                tangents.append(knots[1] - knots[0])
            } else if i == n - 1 {
                tangents.append(knots[n - 1] - knots[n - 2])
            } else {
                tangents.append((knots[i + 1] - knots[i - 1]) * 0.5)
            }
        }

        // Carry one perpendicular along the curve rather than re-deriving it
        // per point: a fresh "up minus its along-track part" flips when the
        // track goes vertical, and a rider built on it flips with it.
        var normal = PathSpline.firstNormal(along: tangents[0])
        var normals: [Vector3] = [normal]
        for i in 1 ..< n {
            normal = PathSpline.transported(normal, from: tangents[i - 1], to: tangents[i])
            normals.append(normal)
        }

        floats.reserveCapacity(9 * n)
        for i in 0 ..< n {
            let p = knots[i] * scale
            let t = tangents[i] * scale
            let u = normals[i]
            floats.append(contentsOf: [Float(p.x), Float(p.y), Float(p.z),
                                       Float(t.x), Float(t.y), Float(t.z),
                                       Float(u.x), Float(u.y), Float(u.z)])
        }
        count = n
    }

    /// A unit vector across the track at its start: world up where the track
    /// is not running straight up, and world z where it is.
    private static func firstNormal(along tangent: Vector3) -> Vector3 {
        let direction = tangent.normalized
        var reference = Vector3.unitY
        if abs(direction.dot(reference)) > 0.99 { reference = .unitZ }
        return (reference - direction * direction.dot(reference)).normalized
    }

    /// `normal` rotated by the same turn that takes one tangent to the next,
    /// then squared back up against the new one.
    private static func transported(_ normal: Vector3,
                                    from previous: Vector3,
                                    to next: Vector3) -> Vector3 {
        let a = previous.normalized
        let b = next.normalized
        var carried = normal
        let axis = a.cross(b)
        let sine = axis.length
        if sine > 1e-9 {
            let unit = axis / sine
            let angle = atan2(sine, a.dot(b))
            // Rodrigues' rotation, the one turn that takes a onto b.
            carried = carried * cos(angle)
                + unit.cross(carried) * sin(angle)
                + unit * (unit.dot(carried) * (1 - cos(angle)))
        }
        let squared = carried - b * b.dot(carried)
        return squared.lengthSquared > 1e-12
            ? squared.normalized
            : PathSpline.firstNormal(along: b)
    }
}
