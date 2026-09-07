import Foundation

/// A smooth curve through a list of points, fitted by John Hobby's method:
/// every gap between two points becomes one cubic Bézier, and the control
/// points are chosen so the bend flows evenly through each point instead of
/// being decided by its neighbors alone.
///
/// The fit solves one small linear system for the direction the curve takes
/// at every point, asking that the curvature arriving at a point match the
/// curvature leaving it. The result is what a practiced hand draws through a
/// few dots: no flat spots, no bulges, and a circle when the dots sit on one.
/// The classic through-the-points spline (`Spline.catmullRom`) sets each
/// tangent from the two neighbors and nothing else, which is cheaper and
/// local, but it flattens between far-apart points and swells between close
/// ones. This curve looks at the whole run.
///
/// Two settings shape it, both from the technique's own vocabulary:
/// - `tension` pulls the control points in toward the chord. `1` is the
///   natural fit; `2` hugs the straight line between the points; values run
///   from `0.75` up.
/// - `curl` says how the two ends of an open curve bend. `1`, the default,
///   gives an end the same bend as the point after it, so three points on a
///   circle come out as that circle. `0` lets the ends run straight, the way
///   a natural spline does.
///
/// A closed curve has no ends, so `curl` does nothing there and the fit wraps
/// around the seam. `startDirection` and `endDirection` pin the direction the
/// curve leaves and arrives in, overriding the curl at that end.
///
/// ```swift
/// let spline = HobbySpline(through: dots, closed: true)
/// drawShape(spline.shape)               // fill and stroke it like any shape
/// for s in spline.segments { … }        // or read the Béziers themselves
/// ```
///
/// The bare call is `drawCurve(points, spline: .hobby)`.
public struct HobbySpline: Equatable, Sendable {

    /// One cubic Bézier of the fit, from one given point to the next.
    public struct Segment: Equatable, Sendable {
        public var start: Vector2
        public var control1: Vector2
        public var control2: Vector2
        public var end: Vector2

        public init(start: Vector2, control1: Vector2, control2: Vector2, end: Vector2) {
            self.start = start
            self.control1 = control1
            self.control2 = control2
            self.end = end
        }

        /// The point a fraction `t` (0...1) along the Bézier.
        public func point(at t: Double) -> Vector2 {
            let u = 1 - t
            return start * (u * u * u)
                + control1 * (3 * u * u * t)
                + control2 * (3 * u * t * t)
                + end * (t * t * t)
        }

        /// The direction of travel a fraction `t` along the Bézier, unit length.
        public func direction(at t: Double) -> Vector2 {
            let u = 1 - t
            let d = (control1 - start) * (3 * u * u)
                + (control2 - control1) * (6 * u * t)
                + (end - control2) * (3 * t * t)
            return d.normalized
        }
    }

    /// The points the curve passes through, in order. Consecutive repeats are
    /// dropped, and a closed run whose last point repeats its first loses it.
    public let points: [Vector2]
    public let isClosed: Bool
    public let tension: Double
    public let curl: Double
    /// The Béziers of the fit, one per gap (one per point when closed).
    public let segments: [Segment]

    /// Fit the curve. `startDirection` and `endDirection` apply to an open
    /// curve only and need not be unit length.
    public init(through points: [Vector2], closed: Bool = false, tension: Double = 1, curl: Double = 1,
                startDirection: Vector2? = nil, endDirection: Vector2? = nil) {
        let knots = HobbySpline.distinct(points, closed: closed)
        self.points = knots
        self.isClosed = closed
        self.tension = max(tension, 0.75)
        self.curl = max(curl, 0)
        self.segments = HobbySpline.fit(knots, closed: closed, tension: self.tension, curl: self.curl,
                                        startDirection: startDirection, endDirection: endDirection)
    }

    /// The fit as a `Path` of cubic curves, closed when the spline is.
    public var path: Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for s in segments {
            path.cubicCurve(to: s.end, control1: s.control1, control2: s.control2)
        }
        if isClosed { path.close() }
        return path
    }

    /// The fit sampled into a polygonal contour.
    public var contour: Contour {
        Contour(sampledPoints(), closed: isClosed)
    }

    /// The fit as a single-contour shape, ready for `drawShape`.
    public var shape: Shape { Shape(contours: [contour]) }

    /// The whole curve flattened to points, the first point included. On a
    /// closed curve the final sample, which lands back on the start, is left
    /// out, since the closed contour already implies it.
    func sampledPoints() -> [Vector2] {
        guard let first = points.first else { return [] }
        guard !segments.isEmpty else { return points }
        var out: [Vector2] = [first]
        for s in segments {
            out.append(contentsOf: CurveSampling.cubic(from: s.start, control1: s.control1,
                                                       control2: s.control2, end: s.end))
        }
        if isClosed { out.removeLast() }
        return out
    }

    // MARK: - The fit

    /// Drop consecutive repeats; two points closer than this are one point.
    private static let coincidence = 1e-9

    static func distinct(_ points: [Vector2], closed: Bool) -> [Vector2] {
        var out: [Vector2] = []
        out.reserveCapacity(points.count)
        for p in points {
            if let last = out.last, (p - last).length < coincidence { continue }
            out.append(p)
        }
        if closed, out.count > 1, let first = out.first, let last = out.last, (last - first).length < coincidence {
            out.removeLast()
        }
        return out
    }

    /// Wrap an angle into (-pi, pi].
    private static func reduced(_ angle: Double) -> Double {
        atan2(sin(angle), cos(angle))
    }

    private static func rotated(_ v: Vector2, by angle: Double) -> Vector2 {
        let c = cos(angle), s = sin(angle)
        return Vector2(v.x * c - v.y * s, v.x * s + v.y * c)
    }

    /// How far along the chord a control point sits, as a fraction of the
    /// chord, for a segment leaving at `theta` and arriving at `phi` (both
    /// measured from the chord). Hobby's velocity function, divided by the
    /// tension and held to at most four chords so a hairpin cannot fling a
    /// control point away.
    static func velocity(_ theta: Double, _ phi: Double, tension: Double) -> Double {
        let st = sin(theta), ct = cos(theta)
        let sf = sin(phi), cf = cos(phi)
        let root5 = 5.0.squareRoot()
        let numerator = 2 + 2.0.squareRoot() * (st - sf / 16) * (sf - st / 16) * (ct - cf)
        let denominator = 3 * (1 + 0.5 * (root5 - 1) * ct + 0.5 * (3 - root5) * cf)
        return min(numerator / denominator / tension, 4)
    }

    static func fit(_ knots: [Vector2], closed: Bool, tension: Double, curl: Double,
                    startDirection: Vector2?, endDirection: Vector2?) -> [Segment] {
        let m = knots.count
        guard m >= 2 else { return [] }
        let n = closed ? m : m - 1                       // chords

        var chord: [Vector2] = []
        var d: [Double] = []
        var angle: [Double] = []
        chord.reserveCapacity(n); d.reserveCapacity(n); angle.reserveCapacity(n)
        for k in 0..<n {
            let c = knots[(k + 1) % m] - knots[k]
            chord.append(c)
            d.append(c.length)
            angle.append(c.angle)
        }

        // The turn at each knot: from the chord arriving to the chord leaving.
        // An open curve's two ends have no turn.
        var psi = [Double](repeating: 0, count: n + 1)
        if closed {
            for k in 0..<n { psi[k] = reduced(angle[k] - angle[(k - 1 + n) % n]) }
        } else {
            for k in 1..<n { psi[k] = reduced(angle[k] - angle[k - 1]) }
        }

        // Uniform tension: the same pull at both ends of every chord.
        let a = 1 / tension                              // 1 / tension, both sides
        let inv = tension * tension                      // 1 / a^2

        /// The equation that matches curvature across knot k, as the three
        /// coefficients on theta[k-1], theta[k], theta[k+1] and the right side.
        func interior(_ k: Int, prev dp: Double, next dn: Double, psiHere: Double, psiNext: Double)
            -> (sub: Double, diag: Double, sup: Double, rhs: Double) {
            let A = a * inv / dp
            let B = (3 - a) * inv / dp
            let C = (3 - a) * inv / dn
            let D = a * inv / dn
            return (A, B + C, D, -B * psiHere - D * psiNext)
        }

        var theta: [Double]
        if closed {
            var sub = [Double](repeating: 0, count: n)
            var diag = [Double](repeating: 0, count: n)
            var sup = [Double](repeating: 0, count: n)
            var rhs = [Double](repeating: 0, count: n)
            for k in 0..<n {
                let e = interior(k, prev: d[(k - 1 + n) % n], next: d[k], psiHere: psi[k], psiNext: psi[(k + 1) % n])
                sub[k] = e.sub; diag[k] = e.diag; sup[k] = e.sup; rhs[k] = e.rhs
            }
            theta = solveCyclic(sub: sub, diag: diag, sup: sup, rhs: rhs)
        } else {
            var sub = [Double](repeating: 0, count: n + 1)
            var diag = [Double](repeating: 0, count: n + 1)
            var sup = [Double](repeating: 0, count: n + 1)
            var rhs = [Double](repeating: 0, count: n + 1)
            for k in 1..<n {
                let e = interior(k, prev: d[k - 1], next: d[k], psiHere: psi[k], psiNext: psi[k + 1])
                sub[k] = e.sub; diag[k] = e.diag; sup[k] = e.sup; rhs[k] = e.rhs
            }
            // The ends: a given direction fixes the angle outright; otherwise
            // the curl sets the end's curvature as a multiple of its neighbor's.
            if let dir = startDirection, dir.length > 0 {
                diag[0] = 1
                rhs[0] = reduced(dir.angle - angle[0])
            } else {
                let cc = ((3 - a) * a * a * curl + a * a * a) / (a * a * a * curl + (3 - a) * a * a)
                diag[0] = 1
                sup[0] = cc
                rhs[0] = -cc * psi[1]
            }
            if let dir = endDirection, dir.length > 0 {
                diag[n] = 1
                rhs[n] = reduced(dir.angle - angle[n - 1])
            } else {
                let cc = ((3 - a) * a * a * curl + a * a * a) / (a * a * a * curl + (3 - a) * a * a)
                sub[n] = cc
                diag[n] = 1
                rhs[n] = 0
            }
            if n == 1, startDirection == nil, endDirection == nil {
                // One chord with a curl at both ends has no bend to match, and
                // the two curl equations coincide: the answer is the straight line.
                theta = [0, 0]
            } else {
                theta = solveTridiagonal(sub: sub, diag: diag, sup: sup, rhs: rhs)
            }
        }

        // Each chord's Bézier from the angle it leaves at and the angle it
        // arrives at, the latter read off the next knot's turn and direction.
        var segments: [Segment] = []
        segments.reserveCapacity(n)
        for k in 0..<n {
            let next = closed ? (k + 1) % n : k + 1
            let thetaHere = theta[k]
            let phiNext = -psi[next] - theta[next]
            let rho = velocity(thetaHere, phiNext, tension: tension)
            let sigma = velocity(phiNext, thetaHere, tension: tension)
            let start = knots[k]
            let end = knots[(k + 1) % m]
            let c1 = start + rotated(chord[k], by: thetaHere) * rho
            let c2 = end - rotated(chord[k], by: -phiNext) * sigma
            segments.append(Segment(start: start, control1: c1, control2: c2, end: end))
        }
        return segments
    }

    // MARK: - Solvers

    /// A tridiagonal system by forward elimination and back substitution.
    static func solveTridiagonal(sub: [Double], diag: [Double], sup: [Double], rhs: [Double]) -> [Double] {
        let n = diag.count
        guard n > 0 else { return [] }
        var c = [Double](repeating: 0, count: n)
        var r = [Double](repeating: 0, count: n)
        c[0] = sup[0] / diag[0]
        r[0] = rhs[0] / diag[0]
        if n > 1 {
            for i in 1..<n {
                let denominator = diag[i] - sub[i] * c[i - 1]
                c[i] = sup[i] / denominator
                r[i] = (rhs[i] - sub[i] * r[i - 1]) / denominator
            }
        }
        var x = [Double](repeating: 0, count: n)
        x[n - 1] = r[n - 1]
        if n > 1 {
            for i in stride(from: n - 2, through: 0, by: -1) {
                x[i] = r[i] - c[i] * x[i + 1]
            }
        }
        return x
    }

    /// A cyclic tridiagonal system (the first row also reads the last unknown
    /// through `sub[0]`, the last row the first through `sup[n-1]`), solved as
    /// a plain tridiagonal one plus a rank-one correction.
    static func solveCyclic(sub: [Double], diag: [Double], sup: [Double], rhs: [Double]) -> [Double] {
        let n = diag.count
        guard n > 2 else {
            // Two unknowns: the wrap lands on the same neighbor as the band.
            // Solve the dense two-by-two directly.
            if n == 2 {
                let a00 = diag[0], a01 = sup[0] + sub[0]
                let a10 = sub[1] + sup[1], a11 = diag[1]
                let det = a00 * a11 - a01 * a10
                guard abs(det) > 1e-300 else { return [0, 0] }
                return [(rhs[0] * a11 - a01 * rhs[1]) / det, (a00 * rhs[1] - a10 * rhs[0]) / det]
            }
            if n == 1 { return diag[0] != 0 ? [rhs[0] / diag[0]] : [0] }
            return []
        }
        let topRight = sub[0]          // the corner the first row reads
        let bottomLeft = sup[n - 1]    // the corner the last row reads
        let gamma = -diag[0]
        var band = diag
        band[0] = diag[0] - gamma
        band[n - 1] = diag[n - 1] - bottomLeft * topRight / gamma
        var openSub = sub, openSup = sup
        openSub[0] = 0
        openSup[n - 1] = 0
        let x = solveTridiagonal(sub: openSub, diag: band, sup: openSup, rhs: rhs)
        var u = [Double](repeating: 0, count: n)
        u[0] = gamma
        u[n - 1] = bottomLeft
        let z = solveTridiagonal(sub: openSub, diag: band, sup: openSup, rhs: u)
        let factor = (x[0] + topRight * x[n - 1] / gamma) / (1 + z[0] + topRight * z[n - 1] / gamma)
        return (0..<n).map { x[$0] - factor * z[$0] }
    }
}
