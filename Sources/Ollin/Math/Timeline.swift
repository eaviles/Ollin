import Foundation

/// A value you can interpolate between, so a `Timeline` (or any tween) can blend
/// from one keyframe of it to the next. Conformed by `Double`, `Vector2`, and
/// `Vector3`; conform your own type by defining the straight-line blend.
public protocol Tweenable {
    /// Blend from `a` to `b` by `t` (`0` returns `a`, `1` returns `b`).
    static func lerp(_ a: Self, _ b: Self, _ t: Double) -> Self
}

extension Double: Tweenable {
    public static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
}

extension Vector2: Tweenable {
    public static func lerp(_ a: Vector2, _ b: Vector2, _ t: Double) -> Vector2 { a.lerp(to: b, t) }
}

extension Vector3: Tweenable {
    public static func lerp(_ a: Vector3, _ b: Vector3, _ t: Double) -> Vector3 { a.lerp(to: b, t) }
}

/// A value animated through a sequence of timed keyframes, each with its own
/// easing. Where `@Eased` eases toward a single moving target, a `Timeline`
/// *sequences*: start here, glide to a value over a duration, hold, glide on.
///
/// Build it fluently, then read `value` each frame:
///
/// ```swift
/// let move = Timeline(0.0)
///     .to(100, in: 1.5, ease: .easeOut)   // glide 0 -> 100 over 1.5s
///     .hold(for: 0.5)                       // sit at 100 for 0.5s
///     .to(0, in: 1.0)                       // glide back to 0
/// // each frame:
/// x = move.value
/// ```
///
/// The clock advances in seconds, so a timeline runs the same at any frame rate.
/// A `Timeline` is auto-advanced once per frame **only if it's a stored property
/// on the sketch that exists before the first frame** (declared as a property or
/// assigned in `setup()`), the same rule `@Eased` follows; one created later, or
/// held in a local or a collection, must be advanced by hand. (The camera moves
/// own their timelines internally and advance them explicitly, so this rule never
/// bites there.)
public final class Timeline<Value: Tweenable>: FrameAdvancing {
    private struct Segment {
        let target: Value
        let duration: Double
        let ease: Easing
    }

    private let start: Value
    private var segments: [Segment] = []
    private var clock: Double = 0

    /// When `true`, the clock wraps at the total duration so the sequence repeats.
    public var loops: Bool = false

    /// Begin a timeline resting at `start` (the value at clock 0).
    public init(_ start: Value) { self.start = start }

    /// Glide to `value` over `duration` seconds, shaped by `ease`. Chains.
    @discardableResult
    public func to(_ value: Value, in duration: Double, ease: Easing = .easeInOut) -> Timeline {
        segments.append(Segment(target: value, duration: max(0, duration), ease: ease))
        return self
    }

    /// Hold the current value for `duration` seconds. Chains.
    @discardableResult
    public func hold(for duration: Double) -> Timeline {
        let last = segments.last?.target ?? start
        segments.append(Segment(target: last, duration: max(0, duration), ease: .linear))
        return self
    }

    /// The total length of the sequence, in seconds.
    public var duration: Double { segments.reduce(0) { $0 + $1.duration } }

    /// The interpolated value at the current clock.
    public var value: Value {
        let total = duration
        guard total > 0, !segments.isEmpty else { return segments.last?.target ?? start }
        var t = clock
        if loops {
            t = t.truncatingRemainder(dividingBy: total)
            if t < 0 { t += total }
        }
        if t <= 0 { return start }
        if t >= total { return segments.last!.target }
        var segStart = start
        var acc = 0.0
        for seg in segments {
            if t < acc + seg.duration {
                let local = seg.duration > 0 ? (t - acc) / seg.duration : 1
                return Value.lerp(segStart, seg.target, seg.ease(local))
            }
            acc += seg.duration
            segStart = seg.target
        }
        return segments.last!.target
    }

    /// Progress through the whole sequence, `0...1` (wrapping when `loops`).
    public var progress: Double {
        let total = duration
        guard total > 0 else { return 1 }
        if loops {
            var p = clock.truncatingRemainder(dividingBy: total) / total
            if p < 0 { p += 1 }
            return p
        }
        return Swift.min(Swift.max(clock / total, 0), 1)
    }

    /// Whether a non-looping timeline has reached its end.
    public var isFinished: Bool { !loops && clock >= duration }

    /// Restart the sequence from the beginning.
    public func restart() { clock = 0 }

    /// Jump the clock to `time` seconds (negative clamps to 0).
    public func seek(to time: Double) { clock = Swift.max(0, time) }

    /// Advance the clock by `dt` seconds. A stored timeline is advanced for you
    /// each frame; call this yourself to drive one you hold in a local or a
    /// collection (e.g. `tl.advance(by: deltaTime)`).
    public func advance(by dt: Double) { clock += dt }
}
