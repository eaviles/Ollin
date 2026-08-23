import Foundation

/// One fiber of the Hopf fibration: the circle that a single point of a sphere lifts to,
/// brought down into space where it can be drawn.
public struct HopfFiber: Sendable {
    /// The point on the unit sphere this circle came from. Take the color from here: it is
    /// what shows that the tangle is a picture of a sphere and not just a knot.
    public let base: Vector3
    /// The circle itself, in space, ready for `drawTube(_:closed:)` or any polyline path.
    /// A loop, with the last point next to the first rather than repeating it, so pass
    /// `closed: true` when drawing it. The straight one is the exception: two points, open.
    public let points: [Vector3]
    /// True for the one fiber that comes back as a straight line rather than a circle,
    /// which is the base point at the bottom of the sphere.
    public let isStraight: Bool
}

/// The Hopf fibration: a way of filling a sphere-in-four-dimensions with circles, one for
/// every point of an ordinary sphere, no two of which meet and **every two of which are
/// linked exactly once**.
///
/// That last part is the reason to draw it. Take any two of these circles, anywhere in the
/// tangle, and neither can be pulled free of the other. Projected down into space they come
/// out as nested tori of interlocking rings.
///
/// ```swift
/// let fibers = hopfFibers(over: hopfBases(latitudes: 5, perCircle: 24))
/// for fiber in fibers {
///     fill(Color(hue: (atan2(fiber.base.z, fiber.base.x) / .tau + 1).truncatingRemainder(dividingBy: 1),
///                saturation: 0.7, brightness: 1))
///     drawTube(fiber.points, radius: 0.02, closed: !fiber.isStraight)
/// }
/// ```
///
/// - Parameters:
///   - bases: points on the unit sphere, one circle each. **Use a structured set**, a ring
///     of latitudes or a spiral, rather than scattered ones: the linking only reads when
///     neighboring circles are neighbors, and a random set draws as a ball of wool.
///   - segments: how many points each circle is drawn from.
///   - reach: how long to make the one fiber that comes back straight, since a line has no
///     size of its own to take.
///
/// The circles grow without limit as the base point approaches the bottom of the sphere,
/// because that is where the projection sends things to infinity. `hopfBases` keeps clear
/// of it by default; a base point taken right at it is the straight one, which comes back
/// standing up the world's own up axis.
public func hopfFibers(over bases: [Vector3], segments: Int = 160,
                       reach: Double = 40) -> [HopfFiber] {
    bases.map { hopfFiber(over: $0, segments: segments, reach: reach) }
}

/// One circle of the fibration, over a single point of the unit sphere.
public func hopfFiber(over base: Vector3, segments: Int = 160,
                      reach: Double = 40) -> HopfFiber {
    let world = base.normalized
    let b = hopfMath(world)
    let steps = max(3, segments)
    // The bottom of the sphere is where the projection sends the fiber through infinity, so
    // it comes back as a line rather than a circle. Drawing it matters: it is the axis every
    // other ring is threaded onto, and leaving it out takes the middle out of the picture.
    if b.z <= -1 + 1e-9 {
        return HopfFiber(base: Vector3(0, -1, 0),
                         points: [Vector3(0, -reach, 0), Vector3(0, reach, 0)],
                         isStraight: true)
    }
    var points = [Vector3]()
    points.reserveCapacity(steps)
    for i in 0 ..< steps {
        let t = Double(i) / Double(steps) * .pi * 2
        points.append(hopfWorld(hopfProject(hopfLift(b, t))))
    }
    return HopfFiber(base: world, points: points, isStraight: false)
}

/// Points on the unit sphere arranged as rings of latitude: the arrangement that makes the
/// fibration legible, since each ring lifts to one torus of circles and the rings nest.
///
/// - Parameters:
///   - latitudes: how many rings, spread evenly through `spanning`.
///   - perCircle: how many points around each ring.
///   - spanning: the range of heights the rings sit at, from -1 at the bottom of the sphere
///     to 1 at the top. The default keeps clear of the bottom, where the circles run away.
public func hopfBases(latitudes: Int, perCircle: Int,
                      spanning: ClosedRange<Double> = -0.35 ... 0.9) -> [Vector3] {
    guard latitudes > 0, perCircle > 0 else { return [] }
    return (0 ..< latitudes).flatMap { ring -> [Vector3] in
        let t = latitudes == 1 ? 0.5 : Double(ring) / Double(latitudes - 1)
        let height = spanning.lowerBound + (spanning.upperBound - spanning.lowerBound) * t
        let r = max(0, 1 - height * height).squareRoot()
        // Each ring is turned a little against the last so the circles interleave rather
        // than lining up into visible spokes.
        let twist = Double(ring) * .pi / Double(perCircle)
        return (0 ..< perCircle).map { i in
            let a = Double(i) / Double(perCircle) * .pi * 2 + twist
            return Vector3(cos(a) * r, height, sin(a) * r)
        }
    }
}

/// Points spread evenly over the whole unit sphere along a spiral, the arrangement that
/// covers it most uniformly without a preferred direction. Neighbors along the spiral stay
/// neighbors on the sphere, which is what keeps the fibration readable.
public func hopfBases(spiral count: Int) -> [Vector3] {
    guard count > 0 else { return [] }
    let golden = .pi * (3 - 5.0.squareRoot())
    return (0 ..< count).map { i in
        let height = count == 1 ? 0 : 1 - 2 * Double(i) / Double(count - 1)
        let r = max(0, 1 - height * height).squareRoot()
        let a = Double(i) * golden
        return Vector3(cos(a) * r, height, sin(a) * r)
    }
}

// MARK: - Which way is up
//
// The construction is written the way the mathematics writes it, with the special axis
// third, and the world it is drawn into stands up along its *second*. The two are a quarter
// turn about x apart, and the turn rather than a swap of two coordinates is the point:
// swapping two would mirror the figure, and a mirrored fibration links the other way round,
// which is a different object wearing the same shape.

/// A point of the construction, put where the world can draw it standing up.
func hopfWorld(_ p: Vector3) -> Vector3 { Vector3(p.x, p.z, -p.y) }

/// A point of the world, put back the way the construction reads it.
func hopfMath(_ p: Vector3) -> Vector3 { Vector3(p.x, -p.z, p.y) }

// MARK: - The map itself

/// Lift a point of the unit sphere to one point of its circle in the three-sphere, at
/// parameter `t`.
///
/// This is the standard parameterization, and the square root in it is the whole story: it
/// grows without limit as `base.z` approaches -1, which is the far pole whose circle passes
/// through the point the projection sends to infinity.
func hopfLift(_ base: Vector3, _ t: Double) -> SIMD4<Double> {
    let (a, b, c) = (base.x, base.y, base.z)
    let scale = 1 / (2 * (1 + c)).squareRoot()
    return SIMD4(scale * (1 + c) * cos(t),
                 scale * (1 + c) * sin(t),
                 scale * (a * cos(t) + b * sin(t)),
                 scale * (a * sin(t) - b * cos(t)))
}

/// Where a point of the three-sphere lands in space, projected from the pole the fourth
/// coordinate points at. Circles come down as circles, except the one through the pole
/// itself, which comes down as a line.
func hopfProject(_ p: SIMD4<Double>) -> Vector3 {
    let denominator = 1 - p.w
    guard abs(denominator) > 1e-12 else { return Vector3(0, 0, 0) }
    return Vector3(p.x / denominator, p.y / denominator, p.z / denominator)
}

/// The point of the unit sphere a point of the three-sphere belongs to: the Hopf map itself,
/// and the thing every fiber has in common.
func hopfBase(of p: SIMD4<Double>) -> Vector3 {
    Vector3(2 * (p.x * p.z + p.y * p.w),
            2 * (p.y * p.z - p.x * p.w),
            p.x * p.x + p.y * p.y - p.z * p.z - p.w * p.w)
}
