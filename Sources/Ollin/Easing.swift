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

    /// Shape `t` through the curve. `t` is clamped to `0...1` first, so values
    /// past the ends hold flat rather than overshoot.
    public func callAsFunction(_ t: Double) -> Double {
        curve(Swift.min(Swift.max(t, 0), 1))
    }

    /// Constant speed — no easing.
    public static let linear = Easing { $0 }

    /// Starts slow, accelerates into the target (cubic).
    public static let easeIn = Easing { $0 * $0 * $0 }

    /// Starts fast, decelerates into the target (cubic).
    public static let easeOut = Easing { 1 - pow(1 - $0, 3) }

    /// Slow at both ends, fast through the middle (cubic) — the classic smooth feel.
    public static let easeInOut = Easing { t in
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    /// Hermite smoothstep — a gentler S than `easeInOut`.
    public static let smoothStep = Easing { t in t * t * (3 - 2 * t) }
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
public final class Eased {
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
