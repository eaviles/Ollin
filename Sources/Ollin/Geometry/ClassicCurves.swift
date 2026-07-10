import Foundation

public extension Double {
    /// The golden angle in radians: `pi * (3 - sqrt(5))`, about 137.5 degrees.
    /// It is the "most irrational" slice of a turn, so points advancing by it
    /// never fall into repeating spokes, which is what spaces phyllotaxis
    /// seeds so evenly. The default `angle` of `phyllotaxis(count:spacing:)`.
    static let goldenAngle = Double.pi * (3 - 5.0.squareRoot())
}

/// Vogel's phyllotaxis spiral: the sunflower seed-head arrangement. Point `i`
/// sits a fixed `angle` further around than point `i - 1` and
/// `spacing * sqrt(i)` from the center, so every new seed lands in the gap
/// the earlier ones left and the disk fills evenly at any count.
///
/// The points are centered on the origin; place them with the transform
/// stack (`translate` to the center, `rotate` to spin the head). The array
/// index doubles as the seed's age, oldest at the center, which is the handle
/// for size and color ramps. Pure closed form: no randomness, the same
/// arguments always produce the same points.
///
/// ```swift
/// withState {
///     translate(width / 2, height / 2)
///     for (i, p) in phyllotaxis(count: 600, spacing: 9).enumerated() {
///         drawCircle(p.x, p.y, 3 + Double(i) * 0.01)
///     }
/// }
/// ```
public func phyllotaxis(count: Int, spacing: Double, angle: Double = .goldenAngle) -> [Vector2] {
    guard count > 0 else { return [] }
    return (0..<count).map { i in
        Vector2(angle: Double(i) * angle, length: spacing * Double(i).squareRoot())
    }
}

/// A Lissajous figure: a point swinging side to side `a` times while it bobs
/// up and down `b` times, the curve an oscilloscope draws when two sine waves
/// meet. `phase` offsets the horizontal swing; the default quarter turn gives
/// the open, woven look (at `phase: 0` the figure collapses toward a
/// diagonal). `width` and `height` are the figure's full extents; `height`
/// defaults to `width`.
///
/// Returns a closed `Contour` centered on the origin, one exact period long,
/// so it feeds straight into `drawPolyline`, the shape booleans, hatching,
/// and SVG export. Common frequency ratios are shared: `a: 2, b: 4` traces
/// the same curve as `a: 1, b: 2`.
public func lissajous(a: Int, b: Int, phase: Double = .pi / 2,
                      width: Double, height: Double? = nil,
                      samples: Int = 512) -> Contour {
    let fa = abs(a), fb = abs(b)
    guard fa > 0 || fb > 0 else { return Contour([], closed: true) }
    let g = greatestCommonDivisor(fa, fb)
    let ra = Double(g > 0 ? fa / g : fa)
    let rb = Double(g > 0 ? fb / g : fb)
    let n = max(8, samples)
    let hw = width / 2
    let hh = (height ?? width) / 2
    return Contour((0..<n).map { i in
        let t = Double(i) / Double(n) * .tau
        return Vector2(hw * sin(ra * t + phase), hh * sin(rb * t))
    }, closed: true)
}

/// A rose curve: petals traced by `r = radius * cos(k * theta)` with
/// `k = n / d`. With `d: 1` (the default) an odd `n` gives `n` petals and an
/// even `n` gives `2n`; fractional `k` values (`n: 7, d: 3`) interleave the
/// petals into woven stars. The curve is sampled over exactly the span that
/// closes it once, no retracing, so the contour is plotter-clean.
///
/// Returns a closed `Contour` centered on the origin, starting at
/// `(radius, 0)`. Leave `samples` nil to size the sampling to the curve
/// (longer spans get more points).
public func rose(n: Int, d: Int = 1, radius: Double, samples: Int? = nil) -> Contour {
    let nn = max(1, abs(n))
    let dd = max(1, abs(d))
    let g = greatestCommonDivisor(nn, dd)
    let rn = nn / g
    let rd = dd / g
    let k = Double(rn) / Double(rd)
    // The curve closes over pi*d when n*d is odd, 2*pi*d otherwise.
    let period = (rn * rd) % 2 == 1 ? .pi * Double(rd) : .tau * Double(rd)
    let count = samples.map { max(8, $0) } ?? min(max(512, 256 * rd), 32_768)
    return Contour((0..<count).map { i in
        let theta = Double(i) / Double(count) * period
        return Vector2(angle: theta, length: radius * cos(k * theta))
    }, closed: true)
}

/// A hypotrochoid: the curve of the toy gear set, a pen fixed `pen` units
/// from the center of a `wheel`-radius gear rolling around the *inside* of a
/// fixed `ring`-radius gear. Integer radii guarantee the pen returns to its
/// start, and the sampling covers exactly the revolutions that close the
/// curve once. `pen` less than `wheel` rounds the lobes, `pen` equal to
/// `wheel` gives cusps, `pen` greater loops them.
///
/// Returns a closed `Contour` centered on the origin. Leave `samples` nil to
/// size the sampling to the curve (more revolutions get more points).
public func hypotrochoid(ring: Int, wheel: Int, pen: Double, samples: Int? = nil) -> Contour {
    trochoid(ring: ring, wheel: wheel, pen: pen, samples: samples, rollsInside: true)
}

/// An epitrochoid: the sibling of `hypotrochoid(ring:wheel:pen:samples:)`
/// with the `wheel` gear rolling around the *outside* of the fixed ring, so
/// the lobes bulge outward instead of curving in. Same closure guarantee and
/// sampling rules.
public func epitrochoid(ring: Int, wheel: Int, pen: Double, samples: Int? = nil) -> Contour {
    trochoid(ring: ring, wheel: wheel, pen: pen, samples: samples, rollsInside: false)
}

private func trochoid(ring: Int, wheel: Int, pen: Double, samples: Int?,
                      rollsInside: Bool) -> Contour {
    let ringRadius = max(1, abs(ring))
    let wheelRadius = max(1, abs(wheel))
    // The wheel's center completes wheel / gcd(ring, wheel) laps before the
    // pen lines up with its start again.
    let laps = wheelRadius / greatestCommonDivisor(ringRadius, wheelRadius)
    let count = samples.map { max(8, $0) } ?? min(max(512, 256 * laps), 32_768)
    let R = Double(ringRadius)
    let r = Double(wheelRadius)
    let arm = rollsInside ? R - r : R + r
    let spin = arm / r
    return Contour((0..<count).map { i in
        let t = Double(i) / Double(count) * .tau * Double(laps)
        if rollsInside {
            return Vector2(arm * cos(t) + pen * cos(spin * t),
                           arm * sin(t) - pen * sin(spin * t))
        }
        return Vector2(arm * cos(t) - pen * cos(spin * t),
                       arm * sin(t) - pen * sin(spin * t))
    }, closed: true)
}

public extension Contour {
    /// Chaikin's corner cutting: each pass replaces every corner with two
    /// points a quarter and three quarters of the way along its adjoining
    /// segments, so a jagged polyline relaxes into a flowing curve after two
    /// or three passes. Each pass doubles the point count (`iterations` is
    /// capped at 10); an open contour keeps its exact endpoints, a closed one
    /// rounds all the way around. A contour with fewer than two points
    /// returns unchanged.
    func smoothed(iterations: Int = 2) -> Contour {
        guard iterations > 0, points.count >= 2 else { return self }
        var result = points
        for _ in 0..<min(iterations, 10) {
            result = chaikinPass(result, closed: isClosed)
        }
        return Contour(result, closed: isClosed)
    }
}

public extension Shape {
    /// Chaikin's corner cutting applied to every contour (see
    /// `Contour.smoothed(iterations:)`), keeping the `winding` rule.
    func smoothed(iterations: Int = 2) -> Shape {
        Shape(contours: contours.map { $0.smoothed(iterations: iterations) },
              winding: winding)
    }
}

private func chaikinPass(_ points: [Vector2], closed: Bool) -> [Vector2] {
    let n = points.count
    guard n >= 2 else { return points }
    var out: [Vector2] = []
    out.reserveCapacity(2 * n)
    if closed {
        for i in 0..<n {
            let p = points[i]
            let q = points[(i + 1) % n]
            out.append(p * 0.75 + q * 0.25)
            out.append(p * 0.25 + q * 0.75)
        }
    } else {
        out.append(points[0])
        for i in 0..<(n - 1) {
            let p = points[i]
            let q = points[i + 1]
            out.append(p * 0.75 + q * 0.25)
            out.append(p * 0.25 + q * 0.75)
        }
        out.append(points[n - 1])
    }
    return out
}

private func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
    var a = a
    var b = b
    while b != 0 {
        (a, b) = (b, a % b)
    }
    return max(1, a)
}
