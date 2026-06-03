/// A value a `OneEuroFilter` can smooth. `Double` and `Vector2` conform, so
/// `@Smoothed` works on either. Conformance needs only the arithmetic the filter
/// uses, plus a `smoothingSpeed` magnitude — how the adaptive cutoff measures how
/// fast the signal is moving (the absolute value for a scalar, the length for a
/// vector).
public protocol Smoothable: Sendable {
    static func + (lhs: Self, rhs: Self) -> Self
    static func - (lhs: Self, rhs: Self) -> Self
    static func * (lhs: Self, rhs: Double) -> Self
    /// The magnitude the adaptive cutoff grows with.
    var smoothingSpeed: Double { get }
}

extension Double: Smoothable {
    public var smoothingSpeed: Double { Swift.abs(self) }
}

extension Vector2: Smoothable {
    public var smoothingSpeed: Double { length }
}

/// An adaptive low-pass filter for a noisy live signal: it widens its cutoff as
/// the signal moves fast (less lag) and narrows it when the signal is slow (less
/// jitter), so it beats a fixed low-pass at both ends. The companion to the
/// easing helpers — `@Eased` glides toward a *known target* over a set duration,
/// while this denoises a *stream* whose target you don't know: a jittery
/// `mouseX`/`mouseY`, or the input that arrives once OSC, MIDI, vision, and the
/// phone sensors land.
///
/// Reach for `@Smoothed` for the common case; use this type directly to own the
/// filter state — say, smoothing a value that isn't a sketch property:
///
/// ```swift
/// var filter = OneEuroFilter<Double>(minCutoff: 1, beta: 0.01)
/// let clean = filter.filter(noisy, dt: deltaTime)
/// ```
///
/// Tuning is two knobs: lower `minCutoff` to cut jitter while the signal is slow;
/// raise `beta` to cut lag while it moves fast. The `Vector2` form adapts on the
/// signal's overall speed, so smoothing stays even across x and y.
///
/// Implemented from the technique (Casiez, Roussel & Vogel, *1€ Filter*, CHI
/// 2012), not ported.
public struct OneEuroFilter<Value: Smoothable>: Sendable {
    /// Cutoff frequency (Hz) at rest. Lower is smoother — and laggier — while the
    /// signal barely moves.
    public var minCutoff: Double
    /// Speed coefficient. Higher opens the cutoff up faster as the signal speeds
    /// up, trading smoothness for responsiveness. `0` is a plain fixed low-pass.
    public var beta: Double
    /// Cutoff (Hz) for the internal speed estimate. The paper's `1.0` is almost
    /// always right.
    public var derivativeCutoff: Double

    private var lastRaw: Value?     // previous input, for the speed estimate
    private var lastSpeed: Value?   // previous filtered derivative
    private var lastValue: Value?   // previous filtered output

    public init(minCutoff: Double = 1, beta: Double = 0.007, derivativeCutoff: Double = 1) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    /// The smoothing factor of a one-pole low-pass at `cutoff` Hz over `dt` seconds.
    private func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1 / (2 * Double.pi * cutoff)
        return 1 / (1 + tau / dt)
    }

    /// One low-pass step from `prev` toward `x`.
    private func lowpass(_ x: Value, _ prev: Value, alpha a: Double) -> Value {
        prev + (x - prev) * a
    }

    /// Feed one sample taken `dt` seconds after the last, and read back the
    /// smoothed value. The first sample (no history yet) passes through untouched.
    public mutating func filter(_ x: Value, dt: Double) -> Value {
        guard let lastRaw, let lastSpeed, let lastValue else {
            self.lastRaw = x
            self.lastSpeed = x - x        // the zero of Value's type
            self.lastValue = x
            return x
        }
        guard dt > 0 else { return lastValue }   // no time passed — hold

        // Estimate speed, low-passed at the derivative cutoff.
        let dx = (x - lastRaw) * (1 / dt)
        let speed = lowpass(dx, lastSpeed, alpha: alpha(cutoff: derivativeCutoff, dt: dt))

        // The cutoff grows with that speed; low-pass the value through it.
        let cutoff = minCutoff + beta * speed.smoothingSpeed
        let value = lowpass(x, lastValue, alpha: alpha(cutoff: cutoff, dt: dt))

        self.lastRaw = x
        self.lastSpeed = speed
        self.lastValue = value
        return value
    }

    /// Drop the filter history. The next sample passes through untouched.
    public mutating func reset() {
        lastRaw = nil
        lastSpeed = nil
        lastValue = nil
    }

    /// Re-seat the filter on `value` with zero speed, so the next output starts
    /// from there with no jump.
    public mutating func reset(to value: Value) {
        lastRaw = value
        lastSpeed = value - value
        lastValue = value
    }
}

/// A value that *smooths* whatever noisy input you assign it, a little each frame.
///
/// The denoising counterpart to `@Eased`: assign the raw, jittery value every
/// frame and read back a clean one. The sketch advances the filter automatically,
/// so there's no update step to call. Behind it is a `OneEuroFilter`, an adaptive
/// low-pass that stays responsive when the signal moves fast and steady when it's
/// slow.
///
/// ```swift
/// final class Cursor: Sketch {
///     @Smoothed var p = Vector2.zero                  // gentle defaults
///     @Smoothed(beta: 0.02) var radius = 40.0         // looser — less lag
///     override func draw() {
///         p = Vector2(mouseX, mouseY)                 // feed raw; read smoothed
///         drawCircle(center: p, radius: radius)
///     }
/// }
/// ```
///
/// Works on a `Double` or a `Vector2`. Tune it with `minCutoff` (lower cuts
/// jitter while slow) and `beta` (higher cuts lag while fast); both are reachable
/// live through `$p` for pairing with `@Param`. Because the filter is timed in
/// seconds, it behaves the same at any frame rate.
@propertyWrapper
public final class Smoothed<Value: Smoothable>: FrameAdvancing {
    private var filter: OneEuroFilter<Value>
    private var input: Value
    private var output: Value

    /// The smoothed value; assigning sets the raw input the filter chases.
    public var wrappedValue: Value {
        get { output }
        set { input = newValue }
    }

    /// The filter itself, via `$p` — read the raw value, retune, or `reset`.
    public var projectedValue: Smoothed<Value> { self }

    /// The most recent raw value assigned, before smoothing.
    public var rawValue: Value { input }

    /// Cutoff frequency (Hz) at rest — lower is smoother while the signal is slow.
    public var minCutoff: Double {
        get { filter.minCutoff }
        set { filter.minCutoff = newValue }
    }

    /// Speed coefficient — higher cuts lag while the signal moves fast.
    public var beta: Double {
        get { filter.beta }
        set { filter.beta = newValue }
    }

    public init(wrappedValue: Value, minCutoff: Double = 1, beta: Double = 0.007, derivativeCutoff: Double = 1) {
        self.filter = OneEuroFilter(minCutoff: minCutoff, beta: beta, derivativeCutoff: derivativeCutoff)
        self.input = wrappedValue
        self.output = wrappedValue
    }

    /// Jump straight to `value`, dropping the filter history so it continues from
    /// there with no glide.
    public func set(_ value: Value) {
        input = value
        output = value
        filter.reset(to: value)
    }

    /// Run the filter one step against the latest assigned value. Called by the
    /// sketch each frame.
    func advance(by dt: Double) {
        output = filter.filter(input, dt: dt)
    }
}
