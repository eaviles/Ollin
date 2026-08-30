import Foundation

/// Circle-inversion fractals: the limit set of repeated inversions in an
/// arrangement of circles. Inversion in a circle turns the plane inside out
/// around it (centers map far, the rim stays put); play inversions against
/// each other as a chaos game and every orbit condenses onto the arrangement's
/// limit set, a lace of circles inside circles. Tangent arrangements give the
/// classic gasket lace; separated circles give dust; overlapping ones tear
/// the lace apart.
///
/// ```swift
/// var rng = SplitMix64(seed: 5)
/// let dust = inversionLimitSet(of: circles, count: 40_000, using: &rng)
/// drawPoints(dust, size: 2)
/// ```
///
/// Points draw from `rng`, so the same seed always lands the same dust, and
/// they return raw, ready for `drawPoints`, density tricks, or the SVG path.

/// The inverse of `point` in `circle`: the point on the same ray from the
/// center whose distance satisfies d · d' = r². The rim maps to itself, the
/// center's image runs to infinity (here: returned unchanged, since a chaos
/// game never lands there exactly).
public func inverted(_ point: Vector2, in circle: Circle) -> Vector2 {
    let dx = point.x - circle.center.x
    let dy = point.y - circle.center.y
    let d2 = dx * dx + dy * dy
    guard d2 > 1e-18 else { return point }
    let s = circle.radius * circle.radius / d2
    return Vector2(circle.center.x + dx * s, circle.center.y + dy * s)
}

/// The chaos game over circle inversions: from a point outside the discs,
/// repeatedly invert across a randomly chosen circle of the arrangement,
/// never the one just used (that would undo the step, inversion being its
/// own inverse), recording each visit after a short burn-in. The visits
/// converge onto the limit set: arbitrarily close to each of its points some
/// visit eventually lands.
///
/// - Parameters:
///   - circles: The arrangement (two or more circles; tangent rings give the
///     classic lace, separated circles give dust).
///   - count: How many points to return.
///   - settle: Steps discarded up front while the orbit falls onto the
///     limit set.
///   - rng: The random source; seed it for a reproducible cloud.
/// - Returns: `count` points on the arrangement's limit set, in visit order.
public func inversionLimitSet<R: RandomNumberGenerator>(
    of circles: [Circle],
    count: Int,
    settle: Int = 16,
    using rng: inout R
) -> [Vector2] {
    guard circles.count >= 2, count > 0 else { return [] }

    // Start outside every disc: past the arrangement's bounding corner.
    var maxX = -Double.infinity, maxY = -Double.infinity, maxR = 0.0
    for circle in circles {
        maxX = Swift.max(maxX, circle.center.x + circle.radius)
        maxY = Swift.max(maxY, circle.center.y + circle.radius)
        maxR = Swift.max(maxR, circle.radius)
    }
    var point = Vector2(maxX + maxR, maxY + maxR)

    var points: [Vector2] = []
    points.reserveCapacity(count)
    var previous = -1
    var produced = 0
    var step = 0
    while produced < count {
        // Uniform over every circle except the one just used.
        var pick: Int
        if previous < 0 {
            pick = Int.random(in: 0 ..< circles.count, using: &rng)
        } else {
            pick = Int.random(in: 0 ..< circles.count - 1, using: &rng)
            if pick >= previous { pick += 1 }
        }
        point = inverted(point, in: circles[pick])
        previous = pick
        step += 1
        if step > settle {
            points.append(point)
            produced += 1
        }
    }
    return points
}

// MARK: - Sketch sugar

public extension Sketch {
    /// The chaos game over circle inversions, driven by the seeded `random`,
    /// so `seed(_:)` reproduces the cloud. See
    /// `inversionLimitSet(of:count:settle:using:)`.
    func inversionLimitSet(of circles: [Circle],
                           count: Int,
                           settle: Int = 16) -> [Vector2] {
        Ollin.inversionLimitSet(of: circles, count: count,
                                settle: settle, using: &rng)
    }

    /// The explicit-generator form, mirrored so the free function stays
    /// reachable inside a sketch (an instance method hides every same-name
    /// global).
    func inversionLimitSet<R: RandomNumberGenerator>(of circles: [Circle],
                                                     count: Int,
                                                     settle: Int = 16,
                                                     using rng: inout R) -> [Vector2] {
        Ollin.inversionLimitSet(of: circles, count: count,
                                settle: settle, using: &rng)
    }
}
