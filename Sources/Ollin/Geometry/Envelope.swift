import Foundation

/// A straight line, given as a point it passes through and the direction it runs
/// in. Used as one member of a family of lines whose `envelope` is wanted.
public struct Ray2: Equatable, Sendable {
    /// Where the line starts, or any point on it.
    public var origin: Vector2
    /// Which way it runs. It does not have to be a unit vector.
    public var direction: Vector2

    public init(origin: Vector2, direction: Vector2) {
        self.origin = origin
        self.direction = direction
    }

    /// The point `t` along the line from its origin.
    public func point(at t: Double) -> Vector2 { origin + direction * t }

    /// The distance from `point` to the line the ray runs along, measured in both
    /// directions rather than only forward.
    public func distance(to point: Vector2) -> Double {
        let length = direction.length
        guard length > 1e-12 else { return origin.distance(to: point) }
        return abs((point - origin).cross(direction)) / length
    }
}

/// The curve a family of lines draws without any of them being it.
///
/// Move a line smoothly and it sweeps an area, but the lines all lean against one
/// curve, each one touching it at a single place. That curve is the envelope, and
/// it is where two neighboring lines cross: as the two come together, their
/// crossing settles onto the point where the family touches.
///
/// ```swift
/// for run in envelope(of: rays) { drawPolyline(run.points) }
/// ```
///
/// Neighboring lines that run parallel never cross, so the envelope breaks there.
/// That is why the answer is a list of runs rather than one line: each run is a
/// stretch where the family really does touch something.
///
/// Pass `closed: true` when the family comes back to where it started, so the last
/// line is asked about the first.
public func envelope(of rays: [Ray2], closed: Bool = false) -> [Contour] {
    guard rays.count >= 2 else { return [] }
    var runs: [Contour] = []
    var current: [Vector2] = []
    let pairs = closed ? rays.count : rays.count - 1
    for i in 0 ..< pairs {
        let a = rays[i], b = rays[(i + 1) % rays.count]
        if let crossing = crossing(a, b) {
            current.append(crossing)
        } else if !current.isEmpty {
            if current.count >= 2 { runs.append(Contour(current, closed: false)) }
            current = []
        }
    }
    if current.count >= 2 { runs.append(Contour(current, closed: false)) }
    return runs
}

/// Where two lines cross, or nil when they are parallel enough that the crossing
/// says nothing.
private func crossing(_ a: Ray2, _ b: Ray2) -> Vector2? {
    let denominator = a.direction.cross(b.direction)
    let scale = a.direction.length * b.direction.length
    guard scale > 1e-12, abs(denominator) > 1e-9 * scale else { return nil }
    let t = (b.origin - a.origin).cross(b.direction) / denominator
    return a.origin + a.direction * t
}

/// Where the light comes from.
public enum LightSource: Equatable, Sendable {
    /// A single point, throwing rays in every direction.
    case point(Vector2)
    /// Rays all travelling the same way, as from a source far enough off to have
    /// no direction of its own. The value is the angle they travel at.
    case parallel(Double)

    /// The direction a ray from this source arrives at `point` travelling in.
    public func direction(reaching point: Vector2) -> Vector2 {
        switch self {
        case .point(let origin): return point - origin
        case .parallel(let angle): return Vector2(angle: angle)
        }
    }
}

/// The rays that bounce off `curve` when it is lit from `source`.
///
/// The curve is a run of points, and the surface at each one is taken from its two
/// neighbors, so a curve wants enough points to be smooth. Pass `closed: true` for
/// a loop, which is the usual case: a circular mirror, a cup of coffee.
public func reflectedRays(off curve: [Vector2], from source: LightSource,
                          closed: Bool = false) -> [Ray2] {
    normals(along: curve, closed: closed).map { point, normal in
        let incoming = source.direction(reaching: point).normalized
        // The mirror law, written once: take out twice the part of the ray that
        // runs along the normal.
        let bounced = incoming - normal * (2 * incoming.dot(normal))
        return Ray2(origin: point, direction: bounced)
    }
}

/// The rays that bend as they cross `curve` into a material of refractive `index`.
///
/// A ray meeting the surface too steeply turns back instead of crossing, which is
/// total internal reflection, and those rays are left out rather than faked.
public func refractedRays(through curve: [Vector2], from source: LightSource,
                          index: Double, closed: Bool = false) -> [Ray2] {
    let ratio = index == 0 ? 1 : 1 / index
    return normals(along: curve, closed: closed).compactMap { point, normal in
        let incoming = source.direction(reaching: point).normalized
        // Snell's law in vector form, with the normal turned to face the ray.
        var facing = normal
        var cosIn = -incoming.dot(facing)
        if cosIn < 0 { facing = facing * -1; cosIn = -cosIn }
        let sinOutSquared = ratio * ratio * (1 - cosIn * cosIn)
        guard sinOutSquared <= 1 else { return nil }
        let bent = incoming * ratio + facing * (ratio * cosIn - (1 - sinOutSquared).squareRoot())
        return Ray2(origin: point, direction: bent)
    }
}

/// The bright curve the reflected light gathers on: the envelope of every ray that
/// bounces off `curve`.
///
/// This is the shape in the bottom of a cup on a sunny morning. A circle lit from
/// far away draws a nephroid, the two-lobed curve with a cusp; a circle lit from a
/// point on its own rim draws a cardioid.
///
/// ```swift
/// for run in caustic(off: circlePoints, from: .parallel(0), closed: true) {
///     drawPolyline(run.points)
/// }
/// ```
public func caustic(off curve: [Vector2], from source: LightSource,
                    closed: Bool = false) -> [Contour] {
    envelope(of: reflectedRays(off: curve, from: source, closed: closed), closed: closed)
}

/// The bright curve the *bent* light gathers on, for light crossing into a
/// material of refractive `index`.
public func caustic(through curve: [Vector2], from source: LightSource,
                    index: Double, closed: Bool = false) -> [Contour] {
    envelope(of: refractedRays(through: curve, from: source, index: index, closed: closed),
             closed: closed)
}

/// Each point of the curve with the surface normal there, worked out from the
/// neighbors on either side.
private func normals(along curve: [Vector2], closed: Bool) -> [(Vector2, Vector2)] {
    guard curve.count >= 3 else { return [] }
    var out: [(Vector2, Vector2)] = []
    out.reserveCapacity(curve.count)
    let last = curve.count - 1
    for i in curve.indices {
        let before: Vector2, after: Vector2
        if closed {
            before = curve[(i + last) % curve.count]
            after = curve[(i + 1) % curve.count]
        } else {
            if i == 0 || i == last { continue }
            before = curve[i - 1]
            after = curve[i + 1]
        }
        let along = after - before
        guard along.lengthSquared > 1e-24 else { continue }
        out.append((curve[i], Vector2(-along.y, along.x).normalized))
    }
    return out
}

public extension Sketch {
    /// Draw the envelope of a family of lines with the current `stroke`.
    func drawEnvelope(of rays: [Ray2], closed: Bool = false) {
        for run in envelope(of: rays, closed: closed) { drawPolyline(run.points) }
    }

    /// Draw the caustic of `curve` lit from `source` with the current `stroke`.
    func drawCaustic(off curve: [Vector2], from source: LightSource, closed: Bool = false) {
        for run in caustic(off: curve, from: source, closed: closed) { drawPolyline(run.points) }
    }
}
