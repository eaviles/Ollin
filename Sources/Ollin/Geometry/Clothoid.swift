import Foundation

/// A clothoid: the curve whose bend grows at a steady rate along its own
/// length. It is also called the Euler spiral, or the Cornu spiral when it is
/// drawn whole.
///
/// Every other curve in the toolbox is written as a position. This one is
/// written as a *turn rate*. Start somewhere, face a direction, and turn a
/// little more sharply with every step you take. That single rule is the whole
/// definition, and it produces the one shape that joins a straight line to a
/// circle with no kink in the bend.
///
/// The kink is the point of it. Put a straight road against a circular curve
/// and the bend jumps from nothing to `1 / radius` at the join, so the wheel
/// must be turned instantly. Put a clothoid between them and the bend climbs
/// through every value in between, which is what a hand actually does. Roads,
/// railways, and roller coasters are laid out this way, and it is why a
/// motorway curve feels different from a curve drawn with a compass.
///
/// Four numbers describe one, and they read left to right along the curve:
///
/// - `start` and `heading`: where it begins, and the way it faces there.
/// - `curvature`: how hard it is already bending at the start, as `1 / radius`.
///   Zero is straight. Positive turns to the left.
/// - `curvatureRate`: how much the bend grows over one unit of length. Zero
///   holds the bend, which makes a circular arc, and if `curvature` is zero
///   too it makes a straight line. Both cases are ordinary here rather than
///   special ones, so a chain of clothoids can carry its own straights and
///   arcs with no separate kinds.
/// - `length`: how far along to go.
///
/// Nothing here is random, so the same numbers always produce the same curve.
/// The product is plain geometry, ready for stroking, hatching, the shape
/// booleans, and a pen plotter.
///
/// ```swift
/// // A straight run that eases into a turn of radius 200:
/// let easement = Clothoid.easement(from: Vector2(200, 900), heading: 0,
///                                  radius: 200, length: 260)
/// drawPolyline(easement.points(count: 120))
///
/// // The curve that joins two points with two headings, and nothing else:
/// if let join = Clothoid(from: a, heading: 0, to: b, heading: .pi / 2) {
///     drawPolyline(join.points(count: 120))
/// }
/// ```
///
/// There is no closed form for the position: it is an integral of the heading,
/// and the integral is the Fresnel one. It is worked out here by quadrature to
/// about fifteen digits, so `point(at:)` is exact for drawing purposes at any
/// length.
public struct Clothoid: Equatable, Sendable {

    /// Where the curve begins.
    public var start: Vector2

    /// The way it faces at the start, in radians, measured the way
    /// `Vector2.angle` measures.
    public var heading: Double

    /// How hard it bends at the start, as `1 / radius`. Zero is straight, and
    /// positive turns to the left.
    public var curvature: Double

    /// How much `curvature` grows over one unit of length. This is the number
    /// that makes it a clothoid rather than an arc.
    public var curvatureRate: Double

    /// How far the curve runs, measured along the curve itself.
    public var length: Double

    /// A clothoid from its four numbers. Leave `curvature` out for a curve
    /// that starts straight, which is the usual case.
    public init(
        start: Vector2 = .zero,
        heading: Double = 0,
        curvature: Double = 0,
        curvatureRate: Double,
        length: Double
    ) {
        self.start = start
        self.heading = heading
        self.curvature = curvature
        self.curvatureRate = curvatureRate
        self.length = length
    }
}

// MARK: - Reading the curve

public extension Clothoid {

    /// How hard the curve bends `s` along, as `1 / radius`. It is a straight
    /// line in `s`, which is the definition of the curve.
    func curvature(at s: Double) -> Double { curvature + curvatureRate * s }

    /// The way the curve faces `s` along, in radians. Turning is the integral
    /// of bending, so this is a parabola in `s`.
    func heading(at s: Double) -> Double {
        heading + curvature * s + 0.5 * curvatureRate * s * s
    }

    /// The unit vector the curve faces `s` along.
    func tangent(at s: Double) -> Vector2 { Vector2(angle: heading(at: s)) }

    /// The point `s` along the curve. `s` may run past `length`, or go
    /// negative to read back before the start.
    func point(at s: Double) -> Vector2 {
        let m = clothoidMomenta(0, curvatureRate * s * s, curvature * s, heading)
        return Vector2(start.x + s * m.x, start.y + s * m.y)
    }

    /// Where the curve ends.
    var end: Vector2 { point(at: length) }

    /// The way it faces at the end.
    var endHeading: Double { heading(at: length) }

    /// How hard it bends at the end.
    var endCurvature: Double { curvature(at: length) }

    /// How far the heading turns over the whole curve, in radians. Negative
    /// means it turns to the right.
    var turn: Double { endHeading - heading }

    /// `count` points along the curve, evenly spaced by length, the first at
    /// the start and the last at the end.
    ///
    /// The points are worked out one span at a time rather than each from the
    /// start, so asking for a thousand costs about what asking for one costs
    /// per point.
    func points(count: Int) -> [Vector2] {
        guard count > 1 else { return count == 1 ? [start] : [] }
        let step = length / Double(count - 1)
        var result = [Vector2]()
        result.reserveCapacity(count)
        var here = start
        result.append(here)
        for i in 1..<count {
            let s0 = Double(i - 1) * step
            // The span from s0 to s0 + step, read as a clothoid of its own that
            // begins where the last one stopped.
            let m = clothoidMomenta(
                0,
                curvatureRate * step * step,
                curvature(at: s0) * step,
                heading(at: s0)
            )
            here = Vector2(here.x + step * m.x, here.y + step * m.y)
            result.append(here)
        }
        return result
    }

    /// Points along the curve about `spacing` apart, and never fewer than two.
    ///
    /// A tighter bend gets more points: the count also honors `angle`, the
    /// most the heading may turn between one point and the next, so a hard
    /// corner does not go faceted just because it is short.
    func points(spacing: Double, angle: Double = 0.05) -> [Vector2] {
        let byLength = spacing > 0 ? abs(length) / spacing : 0
        let byTurn = angle > 0 ? abs(turn) / angle : 0
        // Clamped before it becomes an Int, because converting a Double that
        // is huge or not a number traps rather than saturating. 100,000 points
        // is far past what any drawing reads, so the ceiling is a backstop and
        // not a working limit.
        let wanted = max(byLength, byTurn)
        let steps = wanted.isFinite ? Int(min(wanted, 100_000).rounded(.up)) : 100_000
        return points(count: min(max(2, steps + 1), 100_000))
    }

    /// The curve as an open contour, ready to stroke, hatch, or plot.
    func contour(spacing: Double = 2, angle: Double = 0.05) -> Contour {
        Contour(points(spacing: spacing, angle: angle), closed: false)
    }
}

// MARK: - Building one

public extension Clothoid {

    /// The easement: the piece that takes a straight run into a turn of
    /// `radius` over `length` of travel.
    ///
    /// It starts straight and ends bending exactly as hard as the arc it hands
    /// over to, so the two meet with no kink. Positive `radius` turns left,
    /// negative turns right. The heading turns by `length / (2 * radius)` over
    /// the piece, which is half of what the same length of arc would turn: a
    /// clothoid spends the first half of the piece hardly bending at all.
    static func easement(
        from start: Vector2,
        heading: Double,
        radius: Double,
        length: Double
    ) -> Clothoid {
        Clothoid(
            start: start,
            heading: heading,
            curvature: 0,
            curvatureRate: radius == 0 || length == 0 ? 0 : 1 / (radius * length),
            length: length
        )
    }

    /// The single clothoid that leaves `from` facing `heading`, arrives at
    /// `to` facing the other `heading`, and does nothing else.
    ///
    /// This is the curve-fitting question the rest of the type is built for.
    /// Two points and two directions are four facts, and a clothoid has
    /// exactly the freedom to meet them: how hard it bends at the start, how
    /// fast that grows, and how long it runs.
    ///
    /// There are infinitely many answers, because a curve may loop around
    /// before it arrives. The one returned is the plain one, the answer whose
    /// start and end headings each stay within half a turn of the straight
    /// line between the two points.
    ///
    /// Returns `nil` only when the two points are the same, which asks for no
    /// curve at all. A straight line and a circular arc are not special cases:
    /// they come back as a clothoid whose `curvatureRate` is zero.
    ///
    /// ```swift
    /// if let c = Clothoid(from: Vector2(200, 200), heading: 0,
    ///                     to: Vector2(800, 700), heading: .pi / 2) {
    ///     drawPolyline(c.points(count: 200))
    /// }
    /// ```
    init?(from start: Vector2, heading startHeading: Double, to end: Vector2, heading endHeading: Double) {
        let delta = end - start
        let distance = delta.length
        guard distance > 0, distance.isFinite else { return nil }

        // Both headings are measured against the line between the two points,
        // and wrapped to half a turn either way. That choice is what picks the
        // plain answer out of the infinitely many.
        let along = delta.angle
        let phi0 = wrappedToHalfTurn(startHeading - along)
        let phi1 = wrappedToHalfTurn(endHeading - along)
        let sweep = phi1 - phi0

        // The three unknowns collapse to one. Write the curve over 0…1 instead
        // of 0…length, and the heading equation gives the second coefficient
        // away for free, leaving a single number `a` to find: the one that
        // makes the curve arrive on the line rather than beside it.
        var a = 3 * (phi0 + phi1)
        var residual = clothoidMomenta(0, 2 * a, sweep - a, phi0).y
        for _ in 0..<64 {
            if abs(residual) < 1e-14 { break }
            let slope = clothoidMomenta(2, 2 * a, sweep - a, phi0).x
                - clothoidMomenta(1, 2 * a, sweep - a, phi0).x
            guard slope != 0, slope.isFinite else { break }
            let step = residual / slope
            a -= step
            residual = clothoidMomenta(0, 2 * a, sweep - a, phi0).y
            if abs(step) < 1e-14 { break }
        }
        guard abs(residual) < 1e-8 else { return nil }

        let reach = clothoidMomenta(0, 2 * a, sweep - a, phi0).x
        guard reach > 0 else { return nil }
        let length = distance / reach
        guard length > 0, length.isFinite else { return nil }

        self.init(
            start: start,
            heading: startHeading,
            curvature: (sweep - a) / length,
            curvatureRate: 2 * a / (length * length),
            length: length
        )
    }
}

// MARK: - Chains

public extension Array where Element == Clothoid {

    /// The whole chain sampled as one contour, with no point repeated where
    /// two pieces meet.
    func contour(spacing: Double = 2, angle: Double = 0.05, closed: Bool = false) -> Contour {
        var points = [Vector2]()
        for piece in self {
            let part = piece.points(spacing: spacing, angle: angle)
            points.append(contentsOf: points.isEmpty ? part[...] : part.dropFirst())
        }
        if closed, points.count > 1, let first = points.first, let last = points.last,
           first.distanceSquared(to: last) < 1e-18 {
            points.removeLast()
        }
        return Contour(points, closed: closed)
    }

    /// How far the chain runs in total.
    var length: Double { reduce(0) { $0 + $1.length } }

    /// The piece the chain is on `s` along, and how far along that piece it
    /// is. This is what makes a chain drivable: ask for a distance and get
    /// back somewhere to read a point, a heading, or a bend.
    ///
    /// `s` is clamped to the chain, so a distance past the end reads the end.
    func position(at s: Double) -> (piece: Clothoid, distance: Double)? {
        guard let last = self.last else { return nil }
        if s <= 0, let first = self.first { return (first, 0) }
        var remaining = s
        for piece in self {
            if remaining <= piece.length { return (piece, remaining) }
            remaining -= piece.length
        }
        return (last, last.length)
    }

    /// The point `s` along the whole chain.
    func point(at s: Double) -> Vector2? {
        position(at: s).map { $0.piece.point(at: $0.distance) }
    }

    /// The way the chain faces `s` along.
    func heading(at s: Double) -> Double? {
        position(at: s).map { $0.piece.heading(at: $0.distance) }
    }

    /// How hard the chain bends `s` along.
    func curvature(at s: Double) -> Double? {
        position(at: s).map { $0.piece.curvature(at: $0.distance) }
    }
}

/// A smooth path through the points: one clothoid per gap, each leaving a
/// point facing the way the one before it arrived.
///
/// The path passes through every point exactly and never kinks at one. The
/// heading at each point is read off its two neighbors, which is what makes
/// the path depend on the whole list rather than one gap at a time.
///
/// The bend itself may still jump at a point, because a single clothoid per
/// gap has no freedom left to match it. That is the usual trade: a path with
/// no kink, worked out in one pass with nothing to solve across the whole
/// list.
///
/// ```swift
/// let path = clothoidSpline(through: waypoints)
/// drawPolyline(path.contour().points)
/// ```
public func clothoidSpline(through points: [Vector2], closed: Bool = false) -> [Clothoid] {
    guard points.count > 1 else { return [] }
    let count = points.count

    // A point's heading is the direction from the point before it to the one
    // after it. The ends of an open path have only one neighbor, so they take
    // the direction of their own gap.
    var headings = [Double](repeating: 0, count: count)
    for i in 0..<count {
        let previous = i == 0 ? (closed ? points[count - 1] : points[0]) : points[i - 1]
        let next = i == count - 1 ? (closed ? points[0] : points[count - 1]) : points[i + 1]
        let span = next - previous
        headings[i] = span.lengthSquared > 0 ? span.angle : 0
    }

    var pieces = [Clothoid]()
    let gaps = closed ? count : count - 1
    for i in 0..<gaps {
        let j = (i + 1) % count
        if let piece = Clothoid(
            from: points[i], heading: headings[i],
            to: points[j], heading: headings[j]
        ) {
            pieces.append(piece)
        }
    }
    return pieces
}

/// A polyline with every corner replaced by a turn a vehicle could take: an
/// easement in, an arc of `radius`, and an easement back out. The straight
/// runs between the corners come back as part of the chain, so the whole route
/// is one list of clothoids from the first point to the last.
///
/// A plain rounded corner is one arc, and the bend jumps at both ends of it.
/// Here the bend climbs from nothing to `1 / radius` over `easement` of
/// travel, holds through the arc, and falls away again, so the bend never
/// jumps anywhere along the route. That is how a road is laid out, and it is
/// what makes a drawn corner look driven rather than compassed.
///
/// A corner is fitted only as large as its two legs allow. When it does not
/// fit, the radius and the easement are both scaled down by the same factor
/// for that corner alone, which keeps the shape of the turn and only makes it
/// smaller. Each corner may take at most half of each leg it touches, so two
/// corners sharing a leg never run into each other.
///
/// ```swift
/// let route = clothoidCorners(waypoints, radius: 90, easement: 70)
/// drawPolyline(route.contour().points)
/// ```
public func clothoidCorners(
    _ points: [Vector2],
    radius: Double,
    easement: Double,
    closed: Bool = false
) -> [Clothoid] {
    guard points.count > 2, radius > 0, easement > 0 else {
        return straightChain(points, closed: closed)
    }
    let count = points.count
    let firstCorner = closed ? 0 : 1
    let lastCorner = closed ? count - 1 : count - 2
    guard firstCorner <= lastCorner else { return straightChain(points, closed: closed) }

    var pieces = [Clothoid]()
    // Where the last corner let the route go. A closed route has no start of
    // its own, so it waits for the first corner to say where that is.
    var cursor: Vector2? = closed ? nil : points.first
    var firstEntry: Vector2?

    for i in firstCorner...lastCorner {
        let corner = points[i]
        let before = points[(i - 1 + count) % count]
        let after = points[(i + 1) % count]

        let incoming = corner - before
        let outgoing = after - corner
        guard incoming.lengthSquared > 0, outgoing.lengthSquared > 0 else { continue }
        let inDirection = incoming.normalized
        let outDirection = outgoing.normalized

        let deflection = inDirection.angle(to: outDirection)
        let side: Double = deflection < 0 ? -1 : 1
        let bend = abs(deflection)
        guard bend > 1e-9 else { continue }

        // The two easements together turn by `run / turnRadius`, and that may
        // not be more than the corner itself, or they would overshoot before
        // the arc ever began.
        var run = easement
        var turnRadius = radius
        if run > turnRadius * bend { run = turnRadius * bend }

        // How far back from the corner the turn has to begin. Work it out once
        // at the asked-for size, then scale: every length in a corner is
        // proportional to its radius while the easement keeps the same share
        // of it, so one step lands exactly rather than closing in.
        var tangent = cornerTangent(radius: turnRadius, easement: run, bend: bend)
        let room = 0.5 * min(incoming.length, outgoing.length)
        if tangent > room {
            let shrink = room / tangent
            turnRadius *= shrink
            run *= shrink
            tangent = room
        }

        let entryStart = corner - inDirection * tangent
        let entry = Clothoid(
            start: entryStart,
            heading: inDirection.angle,
            curvature: 0,
            curvatureRate: side / (turnRadius * run),
            length: run
        )
        let arc = Clothoid(
            start: entry.end,
            heading: entry.endHeading,
            curvature: side / turnRadius,
            curvatureRate: 0,
            length: max(0, turnRadius * bend - run)
        )
        let exit = Clothoid(
            start: arc.end,
            heading: arc.endHeading,
            curvature: side / turnRadius,
            curvatureRate: -side / (turnRadius * run),
            length: run
        )

        if let from = cursor, from.distance(to: entryStart) > 1e-12 {
            pieces.append(straightRun(from: from, to: entryStart))
        }
        if firstEntry == nil { firstEntry = entryStart }
        pieces.append(entry)
        if arc.length > 0 { pieces.append(arc) }
        pieces.append(exit)
        cursor = exit.end
    }

    guard let from = cursor, let opening = firstEntry else {
        return straightChain(points, closed: closed)
    }
    let finish = closed ? opening : points[count - 1]
    if from.distance(to: finish) > 1e-12 {
        pieces.append(straightRun(from: from, to: finish))
    }
    return pieces
}

/// A run of straight pieces, which is what a route with no corner to round
/// comes back as.
private func straightChain(_ points: [Vector2], closed: Bool) -> [Clothoid] {
    guard points.count > 1 else { return [] }
    let gaps = closed ? points.count : points.count - 1
    return (0..<gaps).compactMap { i in
        let a = points[i], b = points[(i + 1) % points.count]
        return a.distance(to: b) > 0 ? straightRun(from: a, to: b) : nil
    }
}

/// One straight piece: a clothoid that never bends.
private func straightRun(from: Vector2, to: Vector2) -> Clothoid {
    Clothoid(
        start: from,
        heading: (to - from).angle,
        curvature: 0,
        curvatureRate: 0,
        length: from.distance(to: to)
    )
}

/// How far back from a corner the turn has to begin, for a corner made of an
/// easement, an arc of `radius`, and an easement back out.
private func cornerTangent(radius: Double, easement: Double, bend: Double) -> Double {
    let spiral = Clothoid(curvatureRate: 1 / (radius * easement), length: easement)
    let end = spiral.end
    let spiralAngle = spiral.endHeading
    // Where the arc's center sits, measured from the start of the easement.
    let centerX = end.x - radius * sin(spiralAngle)
    let centerY = end.y + radius * cos(spiralAngle)
    // The arc alone would have started `radius * tan(bend / 2)` back from the
    // corner and sat `radius` off the line. The easement pushes it out by the
    // difference, and that shift costs more tangent.
    return centerY * tan(bend / 2) + centerX
}

/// The Cornu spiral: the whole double spiral, drawn from one eye to the other.
///
/// It is one clothoid read in both directions from the point where it is
/// straight. The bend grows without limit either way, so each end winds into a
/// tighter and tighter circle around a point it never reaches. Those two
/// points are the eyes, and they are where the Fresnel integrals converge.
///
/// - Parameters:
///   - size: how far apart the two ends of the drawn curve are.
///   - turns: how many full turns each arm makes before it stops. Past about
///     three the arms are drawing on top of themselves.
///   - count: how many points to return.
///
/// ```swift
/// drawPolyline(eulerSpiral(size: 700, turns: 2.5))
/// ```
public func eulerSpiral(size: Double, turns: Double = 2.5, count: Int = 500) -> [Vector2] {
    guard count > 1, turns > 0 else { return [] }
    // With a bend rate of pi, the curve is the Fresnel pair exactly, and the
    // heading at `t` is `pi * t * t / 2`, so `t` of `2 * sqrt(turns)` has come
    // round `turns` times.
    let reach = 2 * turns.squareRoot()
    let arm = Clothoid(curvatureRate: .pi, length: reach)
    let tip = arm.end
    let span = 2 * tip.length
    let scale = span > 0 ? size / span : 1

    // Read one arm out from the middle, then mirror it through the middle for
    // the other. The curve has half-turn symmetry about its straight point.
    let half = max(2, count / 2)
    let forward = arm.points(count: half)
    var result = [Vector2]()
    result.reserveCapacity(half * 2)
    for p in forward.reversed() { result.append(Vector2(-p.x * scale, -p.y * scale)) }
    for p in forward.dropFirst() { result.append(Vector2(p.x * scale, p.y * scale)) }
    return result
}

// MARK: - The integrals underneath

/// `X = ∫₀¹ τᵏ cos(a τ² / 2 + b τ + c) dτ` and the matching sine, which is all
/// a clothoid ever needs: the curve itself, the fit, and the slope the fit is
/// solved with are each one of these.
///
/// There is no elementary answer, so it is integrated. The phase sweeps by at
/// most `|a| / 2 + |b|` over the range, so the range is cut into pieces that
/// each sweep less than half a radian and an eight-point Gauss-Legendre rule
/// is applied to every piece. That rule is exact for polynomials up to degree
/// fifteen, and over so short a sweep the integrand is nearly one, so the
/// result lands within a few parts in 10^15 whatever the numbers are.
///
/// The alternative is to write it in Fresnel integrals in closed form, which
/// is faster but loses its precision as `a` goes to zero, exactly where a
/// clothoid becomes an arc or a straight line. Those are the cases a chain of
/// them hits most often, so the steady method wins here.
func clothoidMomenta(_ k: Int, _ a: Double, _ b: Double, _ c: Double) -> (x: Double, y: Double) {
    let sweep = abs(a) * 0.5 + abs(b)
    // Clamped before the Int conversion: a Double that is huge or not a number
    // traps on the way in rather than saturating.
    let wanted = sweep.isFinite ? min(sweep / 0.5, 4096).rounded(.up) : 4096
    let panels = max(1, Int(wanted))
    let width = 1.0 / Double(panels)
    let half = width * 0.5

    var sumX = 0.0
    var sumY = 0.0
    for panel in 0..<panels {
        let middle = (Double(panel) + 0.5) * width
        for node in 0..<8 {
            let tau = middle + half * gaussLegendreNodes[node]
            let phase = 0.5 * a * tau * tau + b * tau + c
            var weight = gaussLegendreWeights[node] * half
            switch k {
            case 0: break
            case 1: weight *= tau
            default: weight *= tau * tau
            }
            sumX += weight * cos(phase)
            sumY += weight * sin(phase)
        }
    }
    return (sumX, sumY)
}

/// The eight-point Gauss-Legendre nodes on -1…1.
private let gaussLegendreNodes: [Double] = [
    -0.9602898564975363, -0.7966664774136267, -0.5255324099163290, -0.1834346424956498,
     0.1834346424956498,  0.5255324099163290,  0.7966664774136267,  0.9602898564975363,
]

/// The weights that go with them. They sum to 2, the width of -1…1.
private let gaussLegendreWeights: [Double] = [
    0.1012285362903763, 0.2223810344533745, 0.3137066458778873, 0.3626837833783620,
    0.3626837833783620, 0.3137066458778873, 0.2223810344533745, 0.1012285362903763,
]

/// An angle brought into -pi…pi.
private func wrappedToHalfTurn(_ angle: Double) -> Double {
    var wrapped = angle.truncatingRemainder(dividingBy: 2 * .pi)
    if wrapped > .pi { wrapped -= 2 * .pi }
    if wrapped < -.pi { wrapped += 2 * .pi }
    return wrapped
}
