import Foundation

/// A shaping curve for interpolation: maps normalized progress `0...1` onto an
/// eased `0...1`. Use one to reshape a `lerp`, or hand it to `@Eased` to give a
/// tween its feel.
///
/// ```swift
/// let t = Easing.easeOut(progress)          // reshape progress
/// let x = lerp(left, right, Easing.easeInOut(progress))
/// ```
///
/// The named curves cover the common cases; build a custom one from any closure:
///
/// ```swift
/// let bounceish = Easing { t in t * t * (3 - 2 * t) }
/// ```
public struct Easing: Sendable {
    /// The shaping function. Receives progress already clamped to `0...1`.
    public let curve: @Sendable (Double) -> Double

    public init(_ curve: @escaping @Sendable (Double) -> Double) {
        self.curve = curve
    }

    /// Shape `t` through the curve. The input `t` is clamped to `0...1` first, so
    /// values past the ends hold flat. The *output* is not clamped: the back,
    /// elastic, and bounce curves overshoot `0...1` mid-flight on purpose, then
    /// settle exactly on the endpoints.
    public func callAsFunction(_ t: Double) -> Double {
        curve(Swift.min(Swift.max(t, 0), 1))
    }

    /// Constant speed — no easing.
    public static let linear = Easing { $0 }

    // MARK: Sine

    public static let easeInSine = Easing { 1 - cos(($0 * .pi) / 2) }
    public static let easeOutSine = Easing { sin(($0 * .pi) / 2) }
    public static let easeInOutSine = Easing { -(cos(.pi * $0) - 1) / 2 }

    // MARK: Quadratic

    public static let easeInQuad = Easing { $0 * $0 }
    public static let easeOutQuad = Easing { 1 - (1 - $0) * (1 - $0) }
    public static let easeInOutQuad = Easing { t in
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }

    // MARK: Cubic

    public static let easeInCubic = Easing { $0 * $0 * $0 }
    public static let easeOutCubic = Easing { 1 - pow(1 - $0, 3) }
    public static let easeInOutCubic = Easing { t in
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    // MARK: Quartic

    public static let easeInQuart = Easing { $0 * $0 * $0 * $0 }
    public static let easeOutQuart = Easing { 1 - pow(1 - $0, 4) }
    public static let easeInOutQuart = Easing { t in
        t < 0.5 ? 8 * t * t * t * t : 1 - pow(-2 * t + 2, 4) / 2
    }

    // MARK: Quintic

    public static let easeInQuint = Easing { pow($0, 5) }
    public static let easeOutQuint = Easing { 1 - pow(1 - $0, 5) }
    public static let easeInOutQuint = Easing { t in
        t < 0.5 ? 16 * pow(t, 5) : 1 - pow(-2 * t + 2, 5) / 2
    }

    // MARK: Exponential

    public static let easeInExpo = Easing { t in
        t == 0 ? 0 : pow(2, 10 * t - 10)
    }
    public static let easeOutExpo = Easing { t in
        t == 1 ? 1 : 1 - pow(2, -10 * t)
    }
    public static let easeInOutExpo = Easing { t in
        if t == 0 { return 0 }
        if t == 1 { return 1 }
        return t < 0.5 ? pow(2, 20 * t - 10) / 2 : (2 - pow(2, -20 * t + 10)) / 2
    }

    // MARK: Circular

    public static let easeInCirc = Easing { 1 - sqrt(1 - pow($0, 2)) }
    public static let easeOutCirc = Easing { sqrt(1 - pow($0 - 1, 2)) }
    public static let easeInOutCirc = Easing { t in
        t < 0.5
            ? (1 - sqrt(1 - pow(2 * t, 2))) / 2
            : (sqrt(1 - pow(-2 * t + 2, 2)) + 1) / 2
    }

    // MARK: Back (overshoots, then settles)

    public static let easeInBack = Easing { t in
        let c1 = 1.70158, c3 = 1.70158 + 1
        return c3 * t * t * t - c1 * t * t
    }
    public static let easeOutBack = Easing { t in
        let c1 = 1.70158, c3 = 1.70158 + 1
        return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
    }
    public static let easeInOutBack = Easing { t in
        let c2 = 1.70158 * 1.525
        return t < 0.5
            ? (pow(2 * t, 2) * ((c2 + 1) * 2 * t - c2)) / 2
            : (pow(2 * t - 2, 2) * ((c2 + 1) * (2 * t - 2) + c2) + 2) / 2
    }

    // MARK: Elastic (springs past, then settles)

    public static let easeInElastic = Easing { t in
        if t == 0 { return 0 }
        if t == 1 { return 1 }
        let c4 = (2 * Double.pi) / 3
        return -pow(2, 10 * t - 10) * sin((t * 10 - 10.75) * c4)
    }
    public static let easeOutElastic = Easing { t in
        if t == 0 { return 0 }
        if t == 1 { return 1 }
        let c4 = (2 * Double.pi) / 3
        return pow(2, -10 * t) * sin((t * 10 - 0.75) * c4) + 1
    }
    public static let easeInOutElastic = Easing { t in
        if t == 0 { return 0 }
        if t == 1 { return 1 }
        let c5 = (2 * Double.pi) / 4.5
        return t < 0.5
            ? -(pow(2, 20 * t - 10) * sin((20 * t - 11.125) * c5)) / 2
            : (pow(2, -20 * t + 10) * sin((20 * t - 11.125) * c5)) / 2 + 1
    }

    // MARK: Bounce

    public static let easeInBounce = Easing { 1 - bounceOut(1 - $0) }
    public static let easeOutBounce = Easing { bounceOut($0) }
    public static let easeInOutBounce = Easing { t in
        t < 0.5
            ? (1 - bounceOut(1 - 2 * t)) / 2
            : (1 + bounceOut(2 * t - 1)) / 2
    }

    // MARK: Aliases & extras

    /// Friendly default for "ease in" — cubic.
    public static let easeIn = easeInCubic
    /// Friendly default for "ease out" — cubic.
    public static let easeOut = easeOutCubic
    /// Friendly default for "ease in and out" — cubic, the classic smooth feel.
    public static let easeInOut = easeInOutCubic
    /// Hermite smoothstep, a gentler S than `easeInOut`. The same curve as the
    /// bare `smoothstep(0, 1, t)`, packaged as an `Easing` for the APIs that
    /// take one.
    public static let smoothstep = Easing { t in t * t * (3 - 2 * t) }
}

/// A property-wrapper value the sketch advances once per frame — the `@Eased`
/// tween and the `@Smoothed` filter. The sketch collects these via reflection
/// (like `@Param`) and steps each one with the frame's `deltaTime`.
protocol FrameAdvancing: AnyObject {
    func advance(by dt: Double)
}

/// The bounce-out shaping function, shared by the three bounce curves.
private func bounceOut(_ t: Double) -> Double {
    let n1 = 7.5625, d1 = 2.75
    var t = t
    if t < 1 / d1 {
        return n1 * t * t
    } else if t < 2 / d1 {
        t -= 1.5 / d1
        return n1 * t * t + 0.75
    } else if t < 2.5 / d1 {
        t -= 2.25 / d1
        return n1 * t * t + 0.9375
    } else {
        t -= 2.625 / d1
        return n1 * t * t + 0.984375
    }
}

/// A value that eases toward whatever you assign it, a little each frame.
///
/// Read it to get the current (animated) value; assign it to set a new target.
/// The sketch advances it automatically every frame, so motion is the default —
/// there's no update step to call.
///
/// ```swift
/// final class Follow: Sketch {
///     @Eased var x = 0.0                              // 0.5s ease-in-out (default)
///     @Eased(duration: 1, curve: .easeOut) var y = 0.0
///     override func draw() {
///         x = mouseX; y = mouseY                      // retarget; the dot glides over
///         drawCircle(x, y, 40 * scale)
///     }
/// }
/// ```
///
/// Assigning the value it's already heading for is a no-op, so it's safe to set
/// the target every frame — only a *change* restarts the tween, from wherever the
/// value currently is. The tween is timed in seconds, so it runs the same at any
/// frame rate.
@propertyWrapper
public final class Eased: FrameAdvancing {
    private var current: Double
    private var start: Double
    private var targetValue: Double
    private var elapsed: Double

    /// How long a retarget takes to complete, in seconds.
    public let duration: Double
    /// The shaping curve the tween follows.
    public let curve: Easing

    /// The current, animated value; assigning sets a new target to ease toward.
    public var wrappedValue: Double {
        get { current }
        set {
            guard newValue != targetValue else { return }
            start = current
            targetValue = newValue
            elapsed = 0
        }
    }

    /// The eased value itself, via `$x` — exposes the target and motion state.
    public var projectedValue: Eased { self }

    /// The value currently being eased toward.
    public var target: Double { targetValue }

    /// Whether the value is still moving toward its target.
    public var isAnimating: Bool { elapsed < duration }

    public init(wrappedValue: Double, duration: Double = 0.5, curve: Easing = .easeInOut) {
        self.current = wrappedValue
        self.start = wrappedValue
        self.targetValue = wrappedValue
        self.elapsed = duration          // start at rest
        self.duration = duration
        self.curve = curve
    }

    /// Jump straight to `value` with no animation (both the value and the target).
    public func set(_ value: Double) {
        current = value
        start = value
        targetValue = value
        elapsed = duration
    }

    /// Advance the tween by `dt` seconds. Called by the sketch each frame.
    func advance(by dt: Double) {
        guard elapsed < duration, duration > 0 else {
            current = targetValue
            return
        }
        elapsed += dt
        let t = Swift.min(elapsed / duration, 1)
        current = start + (targetValue - start) * curve(t)
    }
}
