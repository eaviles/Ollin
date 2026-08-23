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
