import Foundation

/// Circle packing: fill a region with non-overlapping circles, the classic
/// generative-art motif. Two ways to produce a packing are built in, both pure
/// functions of their inputs (seed a `packCircles(in:count:)` run and it always
/// lays the circles down the same way):
///
/// - **Grow-to-touch** (`packCircles`): each circle grows until it touches a
///   neighbor or the bounds, so it ends up the largest it can be without
///   overlapping. `packCircles(in:count:…)` also scatters its own seed points and
///   fills the gaps between big circles with progressively smaller ones (the
///   dense, varied look); `packCircles(around:…)` grows a circle at each point
///   you hand it (blue-noise points make an even foam).
/// - **Front relaxation** (`relaxCircles`): start from circles that overlap and
///   push every overlapping pair apart until none do, holding their radii fixed.
///   The sibling of `Voronoi.relaxed()`, and the way to settle a set you sized
///   yourself.
///
/// The output is `[Circle]`, so it feeds straight into `drawCircles`, the shape
/// booleans, hatching, and SVG export.
///
/// ```swift
/// // Dense, self-seeding pack:
/// var rng = SplitMix64(seed: 7)
/// let packed = packCircles(in: bounds, count: 400, minRadius: 3, maxRadius: 90, using: &rng)
///
/// // Grow-to-touch over a blue-noise set (an even foam):
/// let sites = poissonDisk(in: bounds, radius: 40, using: &rng)
/// let foam = packCircles(around: sites, in: bounds, padding: 2)
/// ```

// MARK: - Grow-to-touch (self-seeding)

/// A dense circle packing of `bounds`: scatter up to `count` seed points and grow
/// a circle at each to the largest radius that clears every circle already placed
/// (and stays inside `bounds`), so big circles land first and smaller ones fill
/// the gaps between them. Draws its seed points from `rng`, so the same seed
/// always produces the same packing.
///
/// The `count` is a target, not a guarantee: packing gets harder as the region
/// fills, so a run stops once `count` circles are placed *or* it has thrown
/// `count * attemptsPerCircle` darts without room for more, whichever comes
/// first. A circle smaller than `minRadius` is never placed (the point is
/// discarded and another tried).
///
/// - Parameters:
///   - bounds: The rectangle to pack.
///   - count: The target number of circles.
///   - minRadius: The smallest circle to place; smaller candidates are dropped.
///   - maxRadius: A cap on how large a circle may grow (no cap by default).
///   - padding: A gap to leave between neighboring circles.
///   - attemptsPerCircle: Darts thrown per target circle before giving up (sets
///     the total dart budget, `count * attemptsPerCircle`).
///   - rng: The random source to draw seed points from; seed it for a
///     reproducible packing.
/// - Returns: The placed circles, largest-first in placement order.
public func packCircles<R: RandomNumberGenerator>(
    in bounds: Rectangle,
    count: Int,
    minRadius: Double,
    maxRadius: Double = .infinity,
    padding: Double = 0,
    attemptsPerCircle: Int = 30,
    using rng: inout R
) -> [Circle] {
    guard count > 0, bounds.width > 0, bounds.height > 0, minRadius > 0 else { return [] }

    var circles: [Circle] = []
    circles.reserveCapacity(count)
    let maxAttempts = count * Swift.max(attemptsPerCircle, 1)
    var attempts = 0

    while circles.count < count, attempts < maxAttempts {
        attempts += 1
        let p = Vector2(bounds.x + Double.random(in: 0 ..< 1, using: &rng) * bounds.width,
                        bounds.y + Double.random(in: 0 ..< 1, using: &rng) * bounds.height)

        // The largest circle at `p` reaches to the nearest wall and to the edge
        // of the nearest existing circle (minus the gap), whichever is closer.
        var r = Swift.min(wallGap(p, bounds), maxRadius)
        for c in circles {
            r = Swift.min(r, p.distance(to: c.center) - c.radius - padding)
            if r < minRadius { break }
        }
        if r >= minRadius {
            circles.append(Circle(center: p, radius: r))
        }
    }
    return circles
}

// MARK: - Grow-to-touch (from given points)

/// Grow a circle at each of `sites` until it touches its nearest neighbor (or the
/// bounds), so the circles just meet without overlapping. Because two circles
/// growing at the same rate meet exactly halfway, each radius is simply half the
/// distance to the nearest other point (less half the `padding`), capped by the
/// bounds and `maxRadius`. A pure function of the points, so it needs no random
/// source; feed it a blue-noise (`poissonDisk`) set for an even, gap-free foam.
///
/// - Parameters:
///   - sites: The circle centers.
///   - bounds: A rectangle each circle stays inside; pass `nil` to leave circles
///     unbounded (grown only against each other).
///   - minRadius: Circles that would come out smaller than this are dropped.
///   - maxRadius: A cap on how large a circle may grow (no cap by default).
///   - padding: A gap to leave between neighboring circles.
/// - Returns: One circle per surviving site, in the order of `sites`.
public func packCircles(
    around sites: [Vector2],
    in bounds: Rectangle? = nil,
    minRadius: Double = 0,
    maxRadius: Double = .infinity,
    padding: Double = 0
) -> [Circle] {
    guard sites.count > 0 else { return [] }

    var circles: [Circle] = []
    circles.reserveCapacity(sites.count)
    for (i, s) in sites.enumerated() {
        var nearest = Double.infinity
        for (j, t) in sites.enumerated() where j != i {
            nearest = Swift.min(nearest, s.distanceSquared(to: t))
        }
        // Half the distance to the nearest neighbor is where equal-rate growth
        // meets; subtract half the gap so the two circles stop `padding` apart.
        var r = nearest.isFinite ? (nearest.squareRoot() - padding) / 2 : maxRadius
        r = Swift.min(r, maxRadius)
        if let bounds { r = Swift.min(r, wallGap(s, bounds)) }
        if r >= minRadius, r > 0 {
            circles.append(Circle(center: s, radius: r))
        }
    }
    return circles
}

// MARK: - Front relaxation

/// Push overlapping circles apart until none overlap, holding each radius fixed.
/// Each iteration nudges every overlapping pair away from each other by half
/// their overlap, then (if `bounds` is given) slides any circle poking out of the
/// region back inside. A few iterations settle most sets; a heavily overlapping
/// one wants more. Deterministic, so it needs no random source, and the sibling
/// of `Voronoi.relaxed()` for circles you sized yourself.
///
/// - Parameters:
///   - circles: The (possibly overlapping) circles to separate.
///   - bounds: A rectangle to keep circles inside; pass `nil` to skip the wall
///     constraint.
///   - iterations: How many separation passes to run.
///   - padding: A gap to open up between neighboring circles.
/// - Returns: The circles with their centers moved apart; radii are unchanged.
public func relaxCircles(
    _ circles: [Circle],
    in bounds: Rectangle? = nil,
    iterations: Int = 20,
    padding: Double = 0
) -> [Circle] {
    guard circles.count > 1, iterations > 0 else { return circles }

    var centers = circles.map(\.center)
    let radii = circles.map(\.radius)
    let n = circles.count

    for _ in 0 ..< iterations {
        for i in 0 ..< n {
            for j in (i + 1) ..< n {
                let delta = centers[j] - centers[i]
                let minDist = radii[i] + radii[j] + padding
                let d = delta.length
                if d >= minDist { continue }
                // A coincident pair has no direction to split along; part them on
                // a fixed axis so the result stays reproducible.
                let dir = d > 1e-9 ? delta * (1 / d) : Vector2(1, 0)
                let push = (minDist - Swift.max(d, 0)) / 2
                centers[i] = centers[i] - dir * push
                centers[j] = centers[j] + dir * push
            }
        }
        if let bounds {
            for i in 0 ..< n {
                centers[i] = clampInside(centers[i], radius: radii[i], bounds: bounds)
            }
        }
    }
    return zip(centers, radii).map { Circle(center: $0, radius: $1) }
}

// MARK: - Helpers (file-private)

/// The radius of the largest circle centered at `p` that fits inside `bounds`,
/// i.e. the distance from `p` to the nearest wall (negative if `p` is outside).
private func wallGap(_ p: Vector2, _ bounds: Rectangle) -> Double {
    Swift.min(Swift.min(p.x - bounds.x, bounds.x + bounds.width - p.x),
              Swift.min(p.y - bounds.y, bounds.y + bounds.height - p.y))
}

/// A center clamped so a circle of `radius` stays wholly inside `bounds` (or
/// centered on the axis when the region is too small to hold it).
private func clampInside(_ c: Vector2, radius: Double, bounds: Rectangle) -> Vector2 {
    func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        lo <= hi ? Swift.min(Swift.max(v, lo), hi) : (lo + hi) / 2
    }
    return Vector2(clamp(c.x, bounds.x + radius, bounds.x + bounds.width - radius),
                   clamp(c.y, bounds.y + radius, bounds.y + bounds.height - radius))
}

// MARK: - Sketch sugar

public extension Sketch {
    /// A dense circle packing of `bounds` (the whole canvas by default): big
    /// circles land first and smaller ones fill the gaps, each grown to touch its
    /// neighbors. Driven by the seeded `random`, so `seed(_:)` makes the packing
    /// reproducible.
    ///
    /// ```swift
    /// seed(7)
    /// let packed = packCircles(count: 400, minRadius: 3 * scale, maxRadius: 90 * scale)
    /// noStroke(); fill(.white)
    /// drawCircles(packed)
    /// ```
    func packCircles(in bounds: Rectangle? = nil,
                     count: Int,
                     minRadius: Double,
                     maxRadius: Double = .infinity,
                     padding: Double = 0,
                     attemptsPerCircle: Int = 30) -> [Circle] {
        Ollin.packCircles(in: bounds ?? canvasRectangle,
                          count: count,
                          minRadius: minRadius,
                          maxRadius: maxRadius,
                          padding: padding,
                          attemptsPerCircle: attemptsPerCircle,
                          using: &rng)
    }

    /// Grow a circle at each of `sites` until it just touches its nearest
    /// neighbor (or the bounds), holding no gaps. A blue-noise set makes an even
    /// foam; deterministic, so it reads straight off the points.
    ///
    /// ```swift
    /// seed(7)
    /// let sites = poissonDisk(radius: 40)
    /// drawCircles(packCircles(around: sites, padding: 2))
    /// ```
    func packCircles(around sites: [Vector2],
                     in bounds: Rectangle? = nil,
                     minRadius: Double = 0,
                     maxRadius: Double = .infinity,
                     padding: Double = 0) -> [Circle] {
        Ollin.packCircles(around: sites,
                          in: bounds ?? canvasRectangle,
                          minRadius: minRadius,
                          maxRadius: maxRadius,
                          padding: padding)
    }

    /// Push overlapping circles apart until none overlap, keeping them inside
    /// `bounds` (the canvas by default). Deterministic, the sibling of
    /// `lloyd(_:)` for circles you sized yourself.
    func relaxCircles(_ circles: [Circle],
                      in bounds: Rectangle? = nil,
                      iterations: Int = 20,
                      padding: Double = 0) -> [Circle] {
        Ollin.relaxCircles(circles,
                           in: bounds ?? canvasRectangle,
                           iterations: iterations,
                           padding: padding)
    }
}
