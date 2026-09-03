import Foundation

/// Re-map a number from one range onto another.
///
/// Linearly maps `value` from `start1...stop1` onto `start2...stop2`:
///
/// ```swift
/// let x = map(sin(time), -1, 1, 0, width)   // -1...1  ->  0...width
/// ```
///
/// By default the result is *not* bounded — a `value` outside the source range
/// maps proportionally outside the destination range. Pass `clamp: true` to
/// hold the result within `start2...stop2` (correct even when that range runs
/// high-to-low).
public func map(_ value: Double,
                _ start1: Double, _ stop1: Double,
                _ start2: Double, _ stop2: Double,
                clamp: Bool = false) -> Double {
    let mapped = start2 + (stop2 - start2) * ((value - start1) / (stop1 - start1))
    guard clamp else { return mapped }
    let lo = Swift.min(start2, stop2)
    let hi = Swift.max(start2, stop2)
    return Swift.min(Swift.max(mapped, lo), hi)
}

/// Linear interpolation: the point `t` of the way from `a` to `b`.
///
/// ```swift
/// let x = lerp(left, right, 0.5)        // midpoint
/// let y = lerp(top, bottom, Easing.easeInOut(progress))   // eased
/// ```
///
/// `t` is not clamped — `t` outside `0...1` extrapolates past the ends. Reshape
/// it with an ``Easing`` curve for non-linear motion.
public func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * t
}

public extension Double {
    /// The circle constant τ = 2π — one full turn in radians.
    static let tau = Double.pi * 2
}

/// Euclidean distance between two points.
///
/// ```swift
/// let d = dist(x, y, mouseX, mouseY)
/// ```
public func dist(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
    let dx = x2 - x1
    let dy = y2 - y1
    return (dx * dx + dy * dy).squareRoot()
}

// MARK: Shaping scalars
//
// The bare shaping vocabulary, spelled with the same names and argument order
// as the shader side, so an expression written in `draw()` carries verbatim
// into per-pixel code. The `Easing` catalog stays the curve library; these are
// its primitives.

/// Hold `x` within `minValue...maxValue`.
///
/// ```swift
/// let r = clamp(radius, 10, 200)
/// ```
public func clamp(_ x: Double, _ minValue: Double, _ maxValue: Double) -> Double {
    Swift.min(Swift.max(x, minValue), maxValue)
}

/// The fractional part of `x`: `fract(2.75)` is `0.75`.
///
/// Floor-based, so it stays continuous through negative values
/// (`fract(-0.25)` is `0.75`) and wrapping a growing value never jumps:
///
/// ```swift
/// let t = fract(time / 3)   // 0...1 progress, every 3 seconds
/// ```
public func fract(_ x: Double) -> Double {
    x - x.rounded(.down)
}

/// `0` below `edge`, `1` at and above it: an `if` as a function.
///
/// ```swift
/// let on = step(0.5, t)   // switches on halfway through
/// ```
///
/// The hard switch of the shaping family; `smoothstep` is its soft sibling.
public func step(_ edge: Double, _ x: Double) -> Double {
    x < edge ? 0 : 1
}

/// The smooth S-ramp between two edges: `0` at or below `edge0`, `1` at or
/// above `edge1`, easing through the Hermite curve `t * t * (3 - 2 * t)` in
/// between.
///
/// ```swift
/// let lit = smoothstep(0.3, 1.0, wave)   // a soft window on a -1...1 wave
/// let s = smoothstep(0, 1, t)            // plain 0...1 reshape (Easing.smoothstep)
/// ```
///
/// The two edges cut a window: everything below `edge0` is off, everything
/// above `edge1` is fully on, and the transition has no corners. Edges also
/// run high-to-low (`smoothstep(1, 0, x)` fades the other way).
public func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
    let t = clamp((x - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)
}

/// Hold `x` within `minValue...maxValue`, for any comparable type. The generic
/// sibling of the `Double` form, so an `Int` index clamps without a cast:
///
/// ```swift
/// let column = clamp(i, 0, columns - 1)
/// ```
public func clamp<T: Comparable>(_ x: T, _ minValue: T, _ maxValue: T) -> T {
    Swift.min(Swift.max(x, minValue), maxValue)
}

/// Hold `x` within `range`: `clamp(t, to: 0...1)`.
public func clamp<T: Comparable>(_ x: T, to range: ClosedRange<T>) -> T {
    Swift.min(Swift.max(x, range.lowerBound), range.upperBound)
}

/// Bring `x` back into `minValue..<maxValue` by whole laps of the range, the
/// circular sibling of `clamp`. Where `clamp` stops a value at the edge, `wrap`
/// carries it around to the far side, so a walker that leaves one edge of the
/// canvas comes back in at the other:
///
/// ```swift
/// x = wrap(x + step, 0, width)
/// let a = wrap(angle, 0, .tau)
/// ```
///
/// Floor-based, so it stays continuous through negative values (the same rule
/// `fract` follows). An empty or reversed range returns `minValue`.
public func wrap(_ x: Double, _ minValue: Double, _ maxValue: Double) -> Double {
    let span = maxValue - minValue
    guard span > 0 else { return minValue }
    return minValue + (x - minValue) - span * ((x - minValue) / span).rounded(.down)
}

/// A signed `-1...1` value remapped onto `0...1`: `x * 0.5 + 0.5`.
///
/// The direct spelling of the most common remap in a sketch, taking a wave or
/// a signed noise sample to a usable fraction:
///
/// ```swift
/// let t = unipolar(sin(time))          // 0...1
/// fill(palette.color(at: t))
/// ```
///
/// `bipolar` is its inverse. (For noise there is a shorter road: `noise(x)`
/// already answers in `0...1`, so `unipolar(signedNoise(x))` is just `noise(x)`.)
public func unipolar(_ x: Double) -> Double {
    x * 0.5 + 0.5
}

/// A `0...1` value remapped onto `-1...1`: `x * 2 - 1`. The inverse of
/// `unipolar`, for when a fraction has to swing both ways:
///
/// ```swift
/// let sway = bipolar(random())         // -1...1
/// ```
public func bipolar(_ x: Double) -> Double {
    x * 2 - 1
}

// MARK: Dividing a whole

/// `count` evenly spaced fractions of `0...1`, for walking a loop by its
/// progress instead of its index:
///
/// ```swift
/// for t in fractions(12) { drawCircle(lerp(80, width - 80, t), y, 20) }
/// ```
///
/// By default the run is `0/count ... (count-1)/count`, the spacing that tiles
/// a circle or a repeating strip with no doubled seam. Pass `inclusive: true`
/// for `count` fractions from `0` through `1` exactly, the spacing of fence
/// posts rather than fence panels. `count` below one returns an empty array.
public func fractions(_ count: Int, inclusive: Bool = false) -> [Double] {
    guard count > 0 else { return [] }
    if inclusive {
        guard count > 1 else { return [0] }
        return (0..<count).map { Double($0) / Double(count - 1) }
    }
    return (0..<count).map { Double($0) / Double(count) }
}

/// `count` evenly spaced angles in radians, one full turn by default: the
/// spokes of a wheel as a sequence.
///
/// ```swift
/// for a in angles(12) { drawCircle(center: polar(a, 300, around: center), radius: 20) }
/// for a in angles(5, from: time) { … }        // the whole ring turns
/// ```
///
/// `from` rotates the whole fan; `turns` opens it to less or more than a full
/// circle (`turns: 0.5` fans across a half). The last angle stops one step
/// short of closing the turn, so the first and last spokes never double up.
public func angles(_ count: Int, from start: Double = 0, turns: Double = 1) -> [Double] {
    fractions(count).map { start + $0 * turns * .tau }
}

// MARK: Points

/// The point at `angle` and `radius` from `center`: polar coordinates as one
/// call, replacing the spelled-out pair
/// `center + Vector2(cos(angle), sin(angle)) * radius`.
///
/// ```swift
/// let p = polar(time, 300, around: center)     // a point riding a circle
/// drawLine(center, polar(a, r, around: center))
/// ```
///
/// Angle in radians, `0` pointing right and increasing clockwise on screen
/// (y grows downward). With no `around:` the point is measured from the
/// origin, which composes with `translate`.
public func polar(_ angle: Double, _ radius: Double, around center: Vector2 = .zero) -> Vector2 {
    center + Vector2(angle: angle, length: radius)
}

public extension Double {
    /// The angle `value` degrees, as radians: `rotate(.degrees(45))`.
    ///
    /// The drawing calls all speak radians; this reads a familiar unit into
    /// them at the call site, with `.turns(_:)` its whole-circle sibling.
    static func degrees(_ value: Double) -> Double { value * .pi / 180 }

    /// The angle `value` whole turns, as radians: `.turns(0.25)` is a quarter
    /// circle, `.turns(1)` all the way around. See also `.degrees(_:)`.
    static func turns(_ value: Double) -> Double { value * .tau }

    /// The vertical field of view of a lens of `millimeters` focal length, as
    /// radians: `fieldOfView: .focalLength(35)`. Measured on a full-frame sensor
    /// (36×24 mm, so `sensorHeight` is 24) the way lenses are named; pass another
    /// `sensorHeight` for a smaller format. A shorter lens sees wider: 24 mm is
    /// about 53°, 35 mm about 38°, 50 mm about 27°, 85 mm about 16°.
    static func focalLength(_ millimeters: Double, sensorHeight: Double = 24) -> Double {
        2 * atan(sensorHeight / (2 * Swift.max(millimeters, 1e-9)))
    }
}

// MARK: Looping progress

public extension Sketch {
    /// How far through a repeating loop the clock is: `0...1` over `duration`
    /// seconds, wrapping back to `0` as each lap completes.
    ///
    /// ```swift
    /// let t = loopProgress(over: 3)         // 0...1, every 3 seconds
    /// let x = lerp(140, width - 140, t)     // cross the canvas, snap back
    /// ```
    ///
    /// `phase` shifts the loop forward by a fraction of its length (`0.5`
    /// starts halfway through). Give neighbors different phases and one loop
    /// animates them in staggered waves:
    ///
    /// ```swift
    /// let t = loopProgress(over: 3, phase: Double(i) / 12)
    /// ```
    func loopProgress(over duration: Double, phase: Double = 0) -> Double {
        guard duration > 0 else { return 0 }
        return fract(time / duration + phase)
    }

    /// Out-and-back progress: `0` up to `1` and back to `0` over `duration`
    /// seconds, repeating. The ping-pong fold of `loopProgress(over:phase:)`:
    /// where that snaps back to `0` at each lap, this retraces its path, so
    /// the motion it drives never jumps.
    ///
    /// ```swift
    /// let t = pingPong(over: 3)             // 0 -> 1 -> 0, every 3 seconds
    /// let x = lerp(140, width - 140, Easing.easeInOut(t))
    /// ```
    func pingPong(over duration: Double, phase: Double = 0) -> Double {
        let t = loopProgress(over: duration, phase: phase) * 2
        return t > 1 ? 2 - t : t
    }
}

// MARK: Timers

public extension Sketch {
    /// True on the one frame that crosses each multiple of `seconds`, so a
    /// periodic event needs no counter of its own.
    ///
    /// ```swift
    /// if every(2) { dots.append(Vector2(random(width), random(height))) }
    /// ```
    ///
    /// The clock starts at `0` and that counts as a crossing, so the first
    /// frame answers `true` and every `seconds` after it does too. `phase`
    /// shifts the beat by a fraction of its own length, the way it shifts a lap
    /// in ``Sketch/loopProgress(over:phase:)``, so two rhythms of one period
    /// can interleave:
    ///
    /// ```swift
    /// if every(2) { … }                 // 0s, 2s, 4s …
    /// if every(2, phase: 0.5) { … }     // 1s, 3s, 5s …
    /// ```
    ///
    /// The answer reads the clock and nothing else, so a recorded run replays
    /// the same beats and an export lands them on the same seconds at any
    /// frame rate. Two limits come with that. A frame long enough to cover more
    /// than one crossing answers `true` once, because one `Bool` can only say
    /// "now" once. And a clock that goes backwards, as a replay does when it
    /// starts over, enters a new period and beats there.
    func every(_ seconds: Double, phase: Double = 0) -> Bool {
        guard seconds > 0 else { return false }
        return floor(time / seconds + phase) != floor(previousTime / seconds + phase)
    }

    /// True on the one frame that crosses `seconds`, and false on every other
    /// frame: a one-shot, for something that starts once, a little way in.
    ///
    /// ```swift
    /// if after(3) { revealed = true }
    /// ```
    ///
    /// Like ``Sketch/every(_:phase:)`` it reads the clock alone, so it fires at
    /// the same second whatever the frame rate.
    func after(_ seconds: Double) -> Bool {
        time >= seconds && previousTime < seconds
    }

    /// True every `n`th frame, counting the first frame as the first beat.
    ///
    /// ```swift
    /// if everyFrames(30) { grid.step() }     // frames 1, 31, 61 …
    /// ```
    ///
    /// The frame-counting sibling of ``Sketch/every(_:phase:)``. Use this one
    /// when the beat belongs to the work rather than to the wall clock: a
    /// simulation that takes a step every few frames keeps its rate whether the
    /// window runs fast or slow, where a beat in seconds does not.
    func everyFrames(_ n: Int) -> Bool {
        guard n > 0 else { return false }
        return (frameCount - 1) % n == 0
    }
}
