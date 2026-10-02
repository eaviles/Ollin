import Foundation

/// A path through space: an ordered run of 3D points, open or closed, with a
/// frame at every point that turns with the path and never twists about it.
///
/// It is the spine a profile travels along (`Mesh.sweep(_:along:)`), and the
/// rail a thing rides when it should face the way the path goes: a bead on a
/// wire, a car on a roller coaster, a camera on a track. The points are joined
/// by straight segments, so a curve wants enough of them;
/// `Curve3D(curveThrough:closed:segments:)` threads a smooth one through a few.
///
/// ```swift
/// let knot = Curve3D(curveThrough: anchors, closed: true)
/// drawMesh(.sweep(Profile.star(points: 5, outerRadius: 0.2, innerRadius: 0.1), along: knot))
///
/// let f = knot.frame(at: time * 0.1)            // a bead riding the loop
/// withState {
///     translate(f.position)
///     rotate(f.rotation)                         // x, y, z onto normal, binormal, tangent
///     drawBox(width: 0.3, height: 0.1, depth: 0.5)
/// }
/// ```
///
/// **The frames do not twist.** Each one is carried to the next by two
/// reflections (the double reflection method), which turns it exactly as far
/// as the path bends and not at all about the path, so a flat ribbon swept
/// along a knot stays flat to the knot instead of corkscrewing. The first
/// frame stands upright: its `binormal` leans toward world up (`+y`), or its
/// `normal` toward `+x` when the path starts straight up or down, so a path
/// heading along `+z` carries a profile exactly the way `Mesh.extrude` does.
/// On a closed curve the frames carried once around generally come back
/// turned (a curve that is not flat makes them), and that leftover turn is
/// spread evenly along the walked length so the loop meets itself with no
/// seam.
public struct Curve3D: Equatable, Sendable {

    /// The points the path runs through, in order.
    public let points: [Vector3]

    /// Whether the last point joins back to the first.
    public let isClosed: Bool

    /// The frame at each point, paired with `points` by index.
    public let frames: [Frame]

    /// The distance walked to each point from the first; one entry per point.
    let walked: [Double]

    /// The distance walked along the segments end to end, plus the closing
    /// segment back to the start when the curve is closed.
    public let length: Double

    /// A path through `points` as given, joined by straight segments. `closed`
    /// joins the last point back to the first.
    public init(_ points: [Vector3], closed: Bool = false) {
        self.init(points, closed: closed, startNormal: Curve3D.uprightNormal)
    }

    /// A path whose first frame's normal `startNormal` picks from the first
    /// tangent (`Mesh.tube(along:)` starts its rings off the tangent crossed
    /// with world up).
    init(_ points: [Vector3], closed: Bool, startNormal: (Vector3) -> Vector3) {
        self.points = points
        self.isClosed = closed
        var walked = [Double]()
        walked.reserveCapacity(points.count)
        var total = 0.0
        for i in points.indices {
            if i > 0 { total += (points[i] - points[i - 1]).length }
            walked.append(total)
        }
        if closed, points.count > 1 { total += (points[0] - points[points.count - 1]).length }
        self.walked = walked
        self.length = total
        self.frames = Curve3D.rotationMinimizingFrames(points, closed: closed, walked: walked,
                                                       length: total, startNormal: startNormal)
    }

    /// A smooth path threaded through `points` (a Catmull-Rom curve, the same
    /// one `Contour(curveThrough:)` draws in the plane), flattened to straight
    /// steps: about `segments` of them between two neighboring points, more
    /// across a long gap and fewer across a short one. Closed loops wrap for a
    /// seamless curve; open ones clamp their ends. Fewer than three points are
    /// kept as given.
    public init(curveThrough points: [Vector3], closed: Bool = false, segments: Int = 16) {
        self.init(Curve3D.catmullRom(through: points, closed: closed, segments: max(segments, 1)),
                  closed: closed)
    }

    /// A copy whose points march an even `spacing` apart along the walked
    /// path, keeping `isClosed`, with the frames worked out again. A sweep lays
    /// one copy of its shape at each point of the path, so a twist or a taper
    /// along a path of few points turns in visible steps; respaced, it turns
    /// smoothly. An open path keeps its last point, so its last step may come
    /// out shorter, as may a closed path's step back to the start. A path of
    /// fewer than two points, or a `spacing` that is not positive, comes back
    /// unchanged.
    public func resampled(spacing: Double) -> Curve3D {
        guard points.count >= 2, spacing > 0, spacing.isFinite, length > 0 else { return self }
        var walk = points
        if isClosed { walk.append(points[0]) }
        var result = [walk[0]]
        var sinceLast = 0.0
        for i in 1..<walk.count {
            let a = walk[i - 1], b = walk[i]
            let segment = (b - a).length
            guard segment > 1e-12 else { continue }
            var t = 0.0
            while sinceLast + (segment - t) >= spacing {
                t += spacing - sinceLast
                result.append(a + (b - a) * (t / segment))
                sinceLast = 0
            }
            sinceLast += segment - t
        }
        // A closed walk that lands exactly back on its start has no closing
        // step left to make.
        if isClosed, result.count > 1, (result[result.count - 1] - result[0]).length < spacing * 1e-9 {
            result.removeLast()
        }
        // An open path keeps its end, however short the last step.
        if !isClosed, let last = points.last, (result[result.count - 1] - last).length > spacing * 1e-9 {
            result.append(last)
        }
        return Curve3D(result, closed: isClosed)
    }

    /// The point a fraction `t` of the way along the path *by walked length*.
    /// An open path clamps `t` to `0...1`; a closed one wraps it, so `1.25`
    /// is a quarter of the way round again and a clock can run straight into
    /// it.
    public func point(at t: Double) -> Vector3 {
        guard let place = locate(t) else { return points.first ?? .zero }
        let a = points[place.index], b = points[(place.index + 1) % points.count]
        return a + (b - a) * place.weight
    }

    /// The frame a fraction `t` of the way along the path by walked length,
    /// the same measure `point(at:)` takes and with the same clamping and
    /// wrapping. Between two points it turns steadily from one point's frame
    /// to the next, and at a point it is that point's frame.
    public func frame(at t: Double) -> Frame {
        guard let place = locate(t) else {
            return frames.first ?? Frame(position: .zero, tangent: .unitZ, normal: .unitX, binormal: .unitY)
        }
        let a = frames[place.index]
        guard place.weight > 0 else { return a }
        let b = frames[(place.index + 1) % frames.count]
        let turn = a.rotation.interpolated(to: b.rotation, place.weight)
        return Frame(position: point(at: t),
                     tangent: Vector3.unitZ.rotated(by: turn),
                     normal: Vector3.unitX.rotated(by: turn),
                     binormal: Vector3.unitY.rotated(by: turn))
    }

    /// Which segment a fraction lands on (its first point's index) and how far
    /// through it; nil for a path with fewer than two points or no length.
    private func locate(_ t: Double) -> (index: Int, weight: Double)? {
        let n = points.count
        guard n >= 2, length > 0, t.isFinite else { return nil }
        let f = isClosed ? t - t.rounded(.down) : Swift.min(Swift.max(t, 0), 1)
        let target = f * length
        // The last point whose walked distance has not passed the target.
        var lo = 0, hi = n - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if walked[mid] <= target { lo = mid } else { hi = mid - 1 }
        }
        if !isClosed && lo == n - 1 { lo = n - 2 }
        let end = lo + 1 < n ? walked[lo + 1] : length
        let span = end - walked[lo]
        let weight = span > 0 ? Swift.min(Swift.max((target - walked[lo]) / span, 0), 1) : 0
        if weight >= 1 { return ((lo + 1) % n, 0) }
        return (lo, weight)
    }
}

public extension Curve3D {
    /// Where a path is and which way it faces at one place: the `tangent` it
    /// runs along, and the `normal` and `binormal` square to it that a
    /// profile is laid out in. The three are unit length and square to each
    /// other, and `binormal` is `tangent × normal`, so normal, binormal, and
    /// tangent stand the way x, y, and z do.
    struct Frame: Equatable, Sendable {
        /// The point on the path.
        public let position: Vector3
        /// The direction the path runs here.
        public let tangent: Vector3
        /// The first direction across the path: where a profile's x goes.
        public let normal: Vector3
        /// The second direction across the path: where a profile's y goes.
        public let binormal: Vector3

        /// The turn that takes the x, y, and z axes onto `normal`, `binormal`,
        /// and `tangent`. `rotate(frame.rotation)` after
        /// `translate(frame.position)` draws the model's xy-plane across the
        /// path and its z-axis along it.
        public var rotation: Rotation3D {
            Rotation3D(columns: normal, binormal, tangent)
        }

        /// The point `offset` away from the path in this frame's plane:
        /// `offset.x` along `normal` and `offset.y` along `binormal`. This is
        /// where a profile's point lands at this place on the path.
        public func point(_ offset: Vector2) -> Vector3 {
            position + normal * offset.x + binormal * offset.y
        }
    }
}

// MARK: - The frames (shared with `Mesh.tube(along:)`)

extension Curve3D {

    /// The first frame's normal for a path starting along `tangent`: upright,
    /// so the binormal leans toward `+y`, or toward `+x` when the path starts
    /// straight up or down. A path along `+z` gets `normal` `+x` and
    /// `binormal` `+y`, the axes `Mesh.extrude` lays a shape out in.
    static func uprightNormal(_ tangent: Vector3) -> Vector3 {
        if abs(tangent.y) < 0.99 {
            let binormal = (Vector3.unitY - tangent * tangent.y).normalized
            return binormal.cross(tangent).normalized
        }
        return (Vector3.unitX - tangent * tangent.x).normalized
    }

    /// The direction the path runs at each point: the difference of the two
    /// neighbors (wrapping on a closed path, one-sided at an open end). A
    /// point whose neighbors coincide borrows the nearest direction that has
    /// a length, and a path with none at all runs along `+z`.
    static func tangents(_ points: [Vector3], closed: Bool) -> [Vector3] {
        let n = points.count
        var tangents = [Vector3?](repeating: nil, count: n)
        for i in 0..<n where n > 1 {
            let d: Vector3
            if closed {
                d = points[(i + 1) % n] - points[(i - 1 + n) % n]
            } else if i == 0 {
                d = points[1] - points[0]
            } else if i == n - 1 {
                d = points[n - 1] - points[n - 2]
            } else {
                d = points[i + 1] - points[i - 1]
            }
            let length = d.length
            if length > 0, length.isFinite { tangents[i] = d / length }
        }
        guard let firstGood = tangents.firstIndex(where: { $0 != nil }) else {
            return [Vector3](repeating: .unitZ, count: n)
        }
        var out = [Vector3](repeating: .unitZ, count: n)
        var last = tangents[firstGood]!
        for i in 0..<n {
            if let t = tangents[i] { last = t }
            out[i] = last
        }
        return out
    }

    /// Rotation-minimizing frames along `points` by double reflection (Wang,
    /// Jüttler, Zheng, and Liu, 2008): each frame is reflected across the
    /// plane bisecting the segment to the next point, then across the plane
    /// that brings its reflected tangent onto the next tangent. Two
    /// reflections make a rotation, and this one turns the frame with the
    /// path without spinning it about the path. `startNormal` picks the first
    /// frame's normal from the first tangent. On a closed path the turn left
    /// over after one trip round is undone gradually, in proportion to the
    /// walked length, so the last frame leads smoothly back into the first.
    static func rotationMinimizingFrames(_ points: [Vector3], closed: Bool,
                                         walked: [Double], length: Double,
                                         startNormal: (Vector3) -> Vector3) -> [Frame] {
        let n = points.count
        guard n > 0 else { return [] }
        let t = tangents(points, closed: closed)
        var r = [Vector3](repeating: .zero, count: n)
        r[0] = perpendicular(startNormal(t[0]), to: t[0])
        for i in 0..<(n - 1) {
            r[i + 1] = reflected(r[i], t[i], from: points[i], to: points[i + 1], toward: t[i + 1])
        }
        if closed, n > 2, length > 0 {
            // Carry the last frame across the closing segment and read how far
            // it has turned from the first one, about the first tangent.
            let back = reflected(r[n - 1], t[n - 1], from: points[n - 1], to: points[0], toward: t[0])
            let s0 = t[0].cross(r[0])
            let theta = atan2(back.dot(s0), back.dot(r[0]))
            for i in 1..<n {
                let turn = -theta * walked[i] / length
                r[i] = perpendicular(Mesh.rotate(r[i], around: t[i], by: turn), to: t[i])
            }
        }
        return (0..<n).map { i in
            Frame(position: points[i], tangent: t[i], normal: r[i], binormal: t[i].cross(r[i]).normalized)
        }
    }

    /// The double reflection's step: `normal` (square to `tangent` at `from`)
    /// carried to `to`, where the path runs along `next`.
    private static func reflected(_ normal: Vector3, _ tangent: Vector3,
                                  from: Vector3, to: Vector3, toward next: Vector3) -> Vector3 {
        var rL = normal, tL = tangent
        let v1 = to - from
        let c1 = v1.dot(v1)
        if c1 > 0, c1.isFinite {
            rL = normal - v1 * (2 / c1 * v1.dot(normal))
            tL = tangent - v1 * (2 / c1 * v1.dot(tangent))
        }
        let v2 = next - tL
        let c2 = v2.dot(v2)
        var out = rL
        if c2 > 1e-24, c2.isFinite {
            out = rL - v2 * (2 / c2 * v2.dot(rL))
        }
        return perpendicular(out, to: next)
    }

    /// `v` with its part along the unit `axis` removed, at unit length; any
    /// direction square to `axis` when nothing is left.
    private static func perpendicular(_ v: Vector3, to axis: Vector3) -> Vector3 {
        let p = v - axis * v.dot(axis)
        let length = p.length
        if length > 1e-12, length.isFinite { return p / length }
        let pick = abs(axis.x) < 0.9 ? Vector3.unitX : Vector3.unitY
        return (pick - axis * pick.dot(axis)).normalized
    }

    /// A Catmull-Rom curve through `anchors`, flattened to points including
    /// the first anchor. Each span takes `segments` steps scaled by its
    /// length against the mean span, at least one and at most eight times
    /// `segments`. A closed loop leaves out the step that lands back on the
    /// start.
    static func catmullRom(through anchors: [Vector3], closed: Bool, segments: Int) -> [Vector3] {
        let n = anchors.count
        guard n >= 3 else { return anchors }
        func at(_ index: Int) -> Vector3 {
            closed ? anchors[((index % n) + n) % n] : anchors[Swift.min(Swift.max(index, 0), n - 1)]
        }
        let spans = closed ? n : n - 1
        let lengths = (0..<spans).map { (at($0 + 1) - at($0)).length }
        let mean = lengths.reduce(0, +) / Double(spans)
        var out = [anchors[0]]
        for i in 0..<spans {
            let p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2)
            let wanted = mean > 0 ? (Double(segments) * lengths[i] / mean).rounded() : 1
            let steps = wanted.isFinite ? Int(Swift.min(Swift.max(wanted, 1), Double(segments * 8))) : 1
            let top = (closed && i == spans - 1) ? steps - 1 : steps
            guard top >= 1 else { continue }
            for s in 1...top {
                let u = Double(s) / Double(steps)
                let u2 = u * u, u3 = u2 * u
                out.append((p1 * 2
                            + (p2 - p0) * u
                            + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * u2
                            + (p1 * 3 - p0 - p2 * 3 + p3) * u3) * 0.5)
            }
        }
        return out
    }
}

extension Rotation3D {
    /// The turn whose matrix has these three columns: the directions the x,
    /// y, and z axes are turned onto. They are taken to be unit length and
    /// square to each other, standing the way x, y, and z do.
    init(columns x: Vector3, _ y: Vector3, _ z: Vector3) {
        let m00 = x.x, m10 = x.y, m20 = x.z
        let m01 = y.x, m11 = y.y, m21 = y.z
        let m02 = z.x, m12 = z.y, m22 = z.z
        let trace = m00 + m11 + m22
        if trace > 0 {
            let s = (trace + 1).squareRoot() * 2
            self.init(x: (m21 - m12) / s, y: (m02 - m20) / s, z: (m10 - m01) / s, w: s / 4)
        } else if m00 > m11 && m00 > m22 {
            let s = (1 + m00 - m11 - m22).squareRoot() * 2
            self.init(x: s / 4, y: (m01 + m10) / s, z: (m02 + m20) / s, w: (m21 - m12) / s)
        } else if m11 > m22 {
            let s = (1 + m11 - m00 - m22).squareRoot() * 2
            self.init(x: (m01 + m10) / s, y: s / 4, z: (m12 + m21) / s, w: (m02 - m20) / s)
        } else {
            let s = (1 + m22 - m00 - m11).squareRoot() * 2
            self.init(x: (m02 + m20) / s, y: (m12 + m21) / s, z: s / 4, w: (m10 - m01) / s)
        }
    }
}
