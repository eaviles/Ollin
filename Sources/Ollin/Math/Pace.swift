import Foundation

/// An even pace along a curve given as a function: which parameter value
/// lies a given fraction of the way along by length, or, for a strip between
/// two such curves, by the area swept.
///
/// A curve written as a function of a parameter, a Lissajous figure or a
/// harmonograph or a knot, rarely moves at one speed: it rushes through some
/// stretches and crawls through others as the parameter runs evenly. A pace
/// measures the curve once and answers the other way round, so a dot driven
/// by `pace.parameter(at: share)` moves at one speed, and the rungs of a
/// ribbon placed at even shares lie evenly however the curves bend.
///
/// ```swift
/// func lissajous(_ t: Double) -> Vector2 { Vector2(sin(3 * t), sin(4 * t)) * 300 }
/// let pace = Pace(byLengthOf: lissajous, period: .tau)
///
/// let dot = lissajous(pace.parameter(at: time * 0.05))   // one speed all the way round
/// ```
///
/// Nothing is sampled for you to keep: the curve is read when the pace is
/// made (the speed at `resolution` places along it and five more within each
/// stretch, integrated by Gauss-Legendre quadrature), and each answer is
/// solved from that measure by Newton's method, so equal shares come out
/// equal to about one part in a billion on a smooth curve rather than to the
/// spacing of a table. The curve's speed is read by differencing, so the
/// function is evaluated a hair either side of each place it is read.
///
/// A pace made with `period:` wraps: a share past 1 runs into the next lap,
/// and the parameter keeps counting, so `parameter(at: share + 1)` is
/// `parameter(at: share) + period` and a loop never jumps. One made with
/// `over:` clamps to its range. A curve that stands still (no length, or no
/// area) paces its parameter evenly.
public struct Pace: Equatable, Sendable {

    /// The parameter values the pace was measured over: one period from 0,
    /// or the range it was given.
    public let range: ClosedRange<Double>

    /// Whether shares past either end wrap round into further periods.
    public let isPeriodic: Bool

    /// The whole length (or area) over `range`.
    public let total: Double

    /// The measure covered by the start of each stretch, `resolution + 1` of
    /// them, the last equal to `total`.
    let covered: [Double]
    /// How fast the measure grows at the start of each stretch (the speed,
    /// or the rate area is swept), per unit of parameter.
    let rates: [Double]

    /// An even pace by length along `curve`, a closed curve that repeats
    /// every `period` of its parameter, measured over `0...period`. The curve
    /// can be 2D or 3D.
    public init<V: Vector>(byLengthOf curve: (Double) -> V, period: Double, resolution: Int = 1024) {
        self.init(range: 0 ... Pace.width(period), periodic: true, resolution: resolution) { t, step, range, periodic in
            Pace.derivative(curve, at: t, step: step, range: range, periodic: periodic).length
        }
    }

    /// An even pace by length along `curve` over the parameter values in
    /// `range`. Shares outside `0...1` clamp to the ends.
    public init<V: Vector>(byLengthOf curve: (Double) -> V, over range: ClosedRange<Double>,
                           resolution: Int = 1024) {
        self.init(range: range, periodic: false, resolution: resolution) { t, step, range, periodic in
            Pace.derivative(curve, at: t, step: step, range: range, periodic: periodic).length
        }
    }

    /// An even pace by the area of the strip between `first` and `second`,
    /// two curves that repeat every `period`: the surface swept by the
    /// straight segment from `first(t)` to `second(t)` as `t` runs. A share
    /// of the period maps to the parameter by which that share of the strip
    /// has been swept, so rungs at even shares (`Mesh.strip(between:and:)`)
    /// cover equal areas. The area is the strip's own, a ruled surface,
    /// worked out exactly across each rung, not two triangles' worth.
    public init(byAreaBetween first: (Double) -> Vector3, and second: (Double) -> Vector3,
                period: Double, resolution: Int = 1024) {
        self.init(range: 0 ... Pace.width(period), periodic: true, resolution: resolution) { t, step, range, periodic in
            Pace.sweptRate(first, second, at: t, step: step, range: range, periodic: periodic)
        }
    }

    /// An even pace by the area of the strip between `first` and `second`
    /// over the parameter values in `range`. Shares outside `0...1` clamp to
    /// the ends.
    public init(byAreaBetween first: (Double) -> Vector3, and second: (Double) -> Vector3,
                over range: ClosedRange<Double>, resolution: Int = 1024) {
        self.init(range: range, periodic: false, resolution: resolution) { t, step, range, periodic in
            Pace.sweptRate(first, second, at: t, step: step, range: range, periodic: periodic)
        }
    }

    /// The parameter value a `fraction` of the way along by the measure
    /// (length or area). A periodic pace wraps the fraction and keeps
    /// counting periods; one over a range clamps it to `0...1`.
    public func parameter(at fraction: Double) -> Double {
        let start = range.lowerBound, width = range.upperBound - range.lowerBound
        guard fraction.isFinite else {
            if isPeriodic { return start + fraction * width }
            return fraction > 0 ? range.upperBound : start
        }
        let laps = isPeriodic ? fraction.rounded(.down) : 0
        let share = isPeriodic ? fraction - laps : min(max(fraction, 0), 1)
        guard total > 0, width > 0 else { return start + (laps + share) * width }
        let n = covered.count - 1
        let target = share * total
        // The last stretch whose start has not passed the target.
        var lo = 0, hi = n - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if covered[mid] <= target { lo = mid } else { hi = mid - 1 }
        }
        let k = lo
        var tau = 0.0
        let gain = covered[k + 1] - covered[k]
        if gain > 0 {
            // Newton's method on the stretch's cubic, kept inside a bracket
            // that halves whenever a step would leave it.
            var low = 0.0, high = 1.0
            tau = min(max((target - covered[k]) / gain, 0), 1)
            for _ in 0..<60 {
                let miss = measure(k, tau) - target
                if abs(miss) <= total * 1e-15 { break }
                if miss < 0 { low = tau } else { high = tau }
                let slope = measureSlope(k, tau)
                var next = slope > 0 ? tau - miss / slope : (low + high) / 2
                if !(next > low && next < high) { next = (low + high) / 2 }
                if abs(next - tau) < 1e-15 { tau = next; break }
                tau = next
            }
        }
        return start + (laps + (Double(k) + tau) / Double(n)) * width
    }

    /// The fraction of the measure (length or area) covered by the
    /// parameter value `parameter`, the inverse of `parameter(at:)`. A
    /// periodic pace counts whole periods past the first, so the answer
    /// keeps growing lap after lap; one over a range clamps to `0...1`.
    public func fraction(at parameter: Double) -> Double {
        let start = range.lowerBound, width = range.upperBound - range.lowerBound
        guard width > 0 else { return 0 }
        guard parameter.isFinite else {
            if isPeriodic { return parameter }
            return parameter > start ? 1 : 0
        }
        var u = (parameter - start) / width
        var laps = 0.0
        if isPeriodic {
            laps = u.rounded(.down)
            u -= laps
        } else {
            u = min(max(u, 0), 1)
        }
        guard total > 0 else { return laps + u }
        let n = covered.count - 1
        let x = u * Double(n)
        let k = min(Int(x), n - 1)
        let s = min(max(measure(k, x - Double(k)), covered[k]), covered[k + 1])
        return laps + s / total
    }
}

// MARK: - Measuring

extension Pace {

    /// A pace over `range` whose measure grows at `rate(t, step, range,
    /// periodic)` per unit of parameter.
    init(range: ClosedRange<Double>, periodic: Bool, resolution: Int,
         rate: (Double, Double, ClosedRange<Double>, Bool) -> Double) {
        self.range = range
        self.isPeriodic = periodic
        let n = min(max(resolution, 1), 1 << 20)
        let start = range.lowerBound
        let width = range.upperBound - range.lowerBound
        guard width > 0, width.isFinite else {
            self.covered = [0, 0]
            self.rates = [0, 0]
            self.total = 0
            return
        }
        let stretch = width / Double(n)
        // Differencing steps a small part of a stretch, so a finer pace reads
        // a finer derivative.
        let step = stretch * 0.05
        func read(_ t: Double) -> Double {
            let r = rate(t, step, range, periodic)
            return r.isFinite ? max(r, 0) : 0
        }
        var covered = [Double](repeating: 0, count: n + 1)
        var rates = [Double](repeating: 0, count: n + 1)
        for k in 0...n { rates[k] = read(start + Double(k) * stretch) }
        for k in 0..<n {
            let t0 = start + Double(k) * stretch
            var sum = 0.0
            for (x, w) in Pace.gaussLegendre { sum += w * read(t0 + x * stretch) }
            covered[k + 1] = covered[k] + sum * stretch
        }
        self.covered = covered
        self.rates = rates
        self.total = covered[n]
    }

    /// Five-point Gauss-Legendre nodes and weights on `0...1`.
    static let gaussLegendre: [(Double, Double)] = {
        let nodes = [(0.0, 0.5688888888888889),
                     (0.5384693101056831, 0.4786286704993665),
                     (-0.5384693101056831, 0.4786286704993665),
                     (0.9061798459386640, 0.2369268850561891),
                     (-0.9061798459386640, 0.2369268850561891)]
        return nodes.map { ((1 + $0.0) / 2, $0.1 / 2) }
    }()

    /// A period read as a width: positive and finite, or no width at all.
    static func width(_ period: Double) -> Double {
        period.isFinite && period > 0 ? period : 0
    }

    /// The measure covered a fraction `tau` of the way through stretch `k`:
    /// the cubic that meets the measure at both ends of the stretch with the
    /// slope the rate gives there.
    func measure(_ k: Int, _ tau: Double) -> Double {
        let h = (range.upperBound - range.lowerBound) / Double(covered.count - 1)
        let c0 = covered[k], c1 = covered[k + 1]
        let m0 = rates[k] * h, m1 = rates[k + 1] * h
        let t2 = tau * tau, t3 = t2 * tau
        return (2 * t3 - 3 * t2 + 1) * c0 + (t3 - 2 * t2 + tau) * m0
            + (3 * t2 - 2 * t3) * c1 + (t3 - t2) * m1
    }

    /// The slope of `measure(k, _:)` at `tau`, per unit of `tau`.
    func measureSlope(_ k: Int, _ tau: Double) -> Double {
        let h = (range.upperBound - range.lowerBound) / Double(covered.count - 1)
        let c0 = covered[k], c1 = covered[k + 1]
        let m0 = rates[k] * h, m1 = rates[k + 1] * h
        let t2 = tau * tau
        return (6 * t2 - 6 * tau) * c0 + (3 * t2 - 4 * tau + 1) * m0
            + (6 * tau - 6 * t2) * c1 + (3 * t2 - 2 * tau) * m1
    }

    /// The derivative of `curve` at `t` by fourth-order differences `step`
    /// apart: centered, or one-sided within two steps of an end of a range
    /// that does not repeat, so the curve is never read past its range.
    static func derivative<V: Vector>(_ curve: (Double) -> V, at t: Double, step h: Double,
                                      range: ClosedRange<Double>, periodic: Bool) -> V {
        if periodic || (t - 2 * h >= range.lowerBound && t + 2 * h <= range.upperBound) {
            return (curve(t - 2 * h) - curve(t - h) * 8 + curve(t + h) * 8 - curve(t + 2 * h)) / (12 * h)
        }
        if t - 2 * h < range.lowerBound {
            return (curve(t) * -25 + curve(t + h) * 48 - curve(t + 2 * h) * 36
                    + curve(t + 3 * h) * 16 - curve(t + 4 * h) * 3) / (12 * h)
        }
        return (curve(t) * 25 - curve(t - h) * 48 + curve(t - 2 * h) * 36
                - curve(t - 3 * h) * 16 + curve(t - 4 * h) * 3) / (12 * h)
    }

    /// How fast the strip from `first(t)` to `second(t)` sweeps area at `t`:
    /// the length of the surface's cross product integrated across the rung.
    static func sweptRate(_ first: (Double) -> Vector3, _ second: (Double) -> Vector3, at t: Double,
                          step: Double, range: ClosedRange<Double>, periodic: Bool) -> Double {
        let a = first(t), b = second(t)
        let da = derivative(first, at: t, step: step, range: range, periodic: periodic)
        let db = derivative(second, at: t, step: step, range: range, periodic: periodic)
        return acrossRung(rung: b - a, start: da, end: db)
    }

    /// The integral over `v` in `0...1` of `|(start + v (end - start)) × rung|`:
    /// the rate a segment sweeps area when its ends move at `start` and
    /// `end`. With `p = start × rung` and `q = (end - start) × rung` the
    /// integrand is the length of `p + v q`, the square root of a quadratic,
    /// integrated in closed form; when `q` is small beside `p` the closed
    /// form would cancel, and the integrand is so nearly straight that
    /// Gauss-Legendre is exact to rounding.
    static func acrossRung(rung: Vector3, start: Vector3, end: Vector3) -> Double {
        let p = start.cross(rung), q = (end - start).cross(rung)
        let pp = p.lengthSquared, qq = q.lengthSquared
        if qq <= pp * 1e-4 {
            var sum = 0.0
            for (x, w) in gaussLegendre { sum += w * (p + q * x).length }
            return sum
        }
        let x0 = p.dot(q) / qq
        let k = p.cross(q).lengthSquared / (qq * qq)
        func primitive(_ x: Double) -> Double {
            let r = (x * x + k).squareRoot()
            if k > 0 { return (x * r + k * asinh(x / k.squareRoot())) / 2 }
            return x * abs(x) / 2
        }
        return qq.squareRoot() * (primitive(1 + x0) - primitive(x0))
    }
}
