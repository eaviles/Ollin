import Foundation

/// A damped spring that carries a value toward a target with real momentum:
/// retarget it mid-flight and the motion bends smoothly instead of restarting,
/// because the velocity carries over. The physical sibling of the easing pair.
/// `@Eased` replays a fixed curve over a fixed duration; a spring has no
/// schedule, just a pull toward wherever the target is now, which is why it
/// feels alive under a target that never stops moving.
///
/// Reach for `@Sprung` for the common case; use this type directly to own the
/// state yourself, say for values that live in an array:
///
/// ```swift
/// var spring = DampedSpring(value: Vector2.zero, duration: 0.6, bounce: 0.3)
/// let p = spring.advance(toward: mouse, by: deltaTime)
/// ```
///
/// Two knobs, both perceptual. `duration` is the response time in seconds,
/// roughly how long a settle takes. `bounce` sets the character: `0` is
/// critically damped (the fastest approach with no overshoot, the default),
/// `0 < bounce <= 1` overshoots and wobbles (1 rings forever), and negative
/// values drag in slowly like moving through honey.
///
/// Each step evaluates the closed-form solution of the damped harmonic
/// oscillator over `dt` (the under-, critically-, and over-damped branches),
/// so the motion is exact and stable at any time step and any frame rate:
/// a frame hitch can never make a spring explode or ring. Implemented from
/// the published treatments (Lowe, *Game Programming Gems 4*, 2004; Juckett,
/// *Damped Springs*, 2012), not ported.
public struct DampedSpring<Value: Smoothable>: Sendable {

    /// The current, animated value.
    public var value: Value

    /// The current rate of change, carried across retargets. Set it directly
    /// (or `kick`) to throw the value.
    public var velocity: Value

    /// The value the spring is pulling toward.
    public var target: Value

    /// The response time in seconds: roughly how long a settle takes (about
    /// one oscillation period when it bounces). Clamped to at least `0.0001`.
    public var duration: Double {
        get { rawDuration }
        set { rawDuration = Swift.max(newValue, 0.0001) }
    }

    /// The character of the settle: `0` never overshoots, up to `1` wobbles
    /// more and more (1 rings forever), negative drags in slowly. Clamped to
    /// `-0.999...1`.
    public var bounce: Double {
        get { rawBounce }
        set { rawBounce = Swift.min(Swift.max(newValue, -0.999), 1) }
    }

    private var rawDuration: Double
    private var rawBounce: Double

    /// A spring at rest on `value`.
    public init(value: Value, duration: Double = 0.5, bounce: Double = 0) {
        self.value = value
        self.velocity = value - value      // the zero of Value's type
        self.target = value
        self.rawDuration = Swift.max(duration, 0.0001)
        self.rawBounce = Swift.min(Swift.max(bounce, -0.999), 1)
    }

    /// Add an impulse: throw the value without moving the target, and it
    /// springs back.
    public mutating func kick(_ impulse: Value) {
        velocity = velocity + impulse
    }

    /// Jump straight to `value` at rest (value, target, and velocity all land
    /// there).
    public mutating func set(_ newValue: Value) {
        value = newValue
        target = newValue
        velocity = newValue - newValue
    }

    /// Retarget and advance in one call, returning the new value; sugar for
    /// setting `target` then calling `advance(by:)`.
    @discardableResult
    public mutating func advance(toward newTarget: Value, by dt: Double) -> Value {
        target = newTarget
        advance(by: dt)
        return value
    }

    /// Advance the spring by `dt` seconds toward `target`: one exact
    /// closed-form step of the damped oscillator.
    public mutating func advance(by dt: Double) {
        guard dt > 0 else { return }

        // The oscillator constants from the perceptual knobs: the undamped
        // angular frequency from the response time, the damping ratio from
        // bounce (>= 0 backs off the critical damping, < 0 over-damps).
        let omega = 2 * Double.pi / rawDuration
        let zeta = rawBounce >= 0 ? 1 - rawBounce : 1 / (1 + rawBounce)

        // The exact state-transition coefficients over dt for the branch this
        // damping ratio is in. Position and velocity are measured from the
        // target (the equilibrium), so:
        //   newOffset   = offset * pp + velocity * pv
        //   newVelocity = offset * vp + velocity * vv
        let pp: Double, pv: Double, vp: Double, vv: Double
        if abs(zeta - 1) < 1e-6 {
            // Critically damped: the double real root -omega.
            let decay = exp(-omega * dt)
            pp = (1 + omega * dt) * decay
            pv = dt * decay
            vp = -omega * omega * dt * decay
            vv = (1 - omega * dt) * decay
        } else if zeta < 1 {
            // Under-damped: a decaying oscillation at the damped frequency.
            let damped = omega * (1 - zeta * zeta).squareRoot()
            let decay = exp(-zeta * omega * dt)
            let c = cos(damped * dt), s = sin(damped * dt)
            pp = decay * (c + (zeta * omega / damped) * s)
            pv = decay * (s / damped)
            vp = -decay * (omega * omega / damped) * s
            vv = decay * (c - (zeta * omega / damped) * s)
        } else {
            // Over-damped: two decaying exponentials, no oscillation.
            let root = omega * (zeta * zeta - 1).squareRoot()
            let z1 = -zeta * omega + root, z2 = -zeta * omega - root
            let e1 = exp(z1 * dt), e2 = exp(z2 * dt)
            let span = z1 - z2
            pp = (z1 * e2 - z2 * e1) / span
            pv = (e1 - e2) / span
            vp = z1 * z2 * (e2 - e1) / span
            vv = (z1 * e1 - z2 * e2) / span
        }

        let offset = value - target
        value = target + offset * pp + velocity * pv
        velocity = offset * vp + velocity * vv
    }
}

/// A value that springs toward whatever you assign it, with momentum.
///
/// The physical sibling of `@Eased` and `@Smoothed`: assign a target and the
/// value is pulled there by a damped spring, advanced automatically every
/// frame. Because the velocity carries across retargets, assigning a new
/// target mid-flight bends the motion instead of restarting it, which is what
/// makes a spring feel alive under a moving target.
///
/// ```swift
/// final class Chase: Sketch {
///     @Sprung var p = Vector2.zero                     // critically damped (default)
///     @Sprung(duration: 0.4, bounce: 0.5) var r = 40.0 // wobbly
///     override func draw() {
///         p = Vector2(mouseX, mouseY)                  // retarget; the dot swings over
///         if mouseIsPressed { r = 90 } else { r = 40 }
///         drawCircle(center: p, radius: r)
///     }
/// }
/// ```
///
/// Works on a `Double` or a `Vector2`. `duration` is the response time in
/// seconds; `bounce` sets the character (`0` never overshoots, positive
/// wobbles, negative drags). Both are reachable live through `$p`, along with
/// `velocity` and `kick(_:)` for throwing the value. The step is the exact
/// closed-form spring solution, so it behaves the same at any frame rate.
@propertyWrapper
public final class Sprung<Value: Smoothable>: FrameAdvancing {
    private var spring: DampedSpring<Value>

    /// The current, animated value; assigning sets the target the spring
    /// pulls toward.
    public var wrappedValue: Value {
        get { spring.value }
        set { spring.target = newValue }
    }

    /// The spring state itself, via `$p`: read `velocity`, retune `duration`
    /// and `bounce`, or `kick` it.
    public var projectedValue: Sprung<Value> { self }

    /// The value the spring is pulling toward.
    public var target: Value { spring.target }

    /// The current rate of change (per second).
    public var velocity: Value {
        get { spring.velocity }
        set { spring.velocity = newValue }
    }

    /// The response time in seconds: roughly how long a settle takes.
    public var duration: Double {
        get { spring.duration }
        set { spring.duration = newValue }
    }

    /// The character of the settle: `0` never overshoots, up to `1` wobbles,
    /// negative drags in slowly.
    public var bounce: Double {
        get { spring.bounce }
        set { spring.bounce = newValue }
    }

    public init(wrappedValue: Value, duration: Double = 0.5, bounce: Double = 0) {
        spring = DampedSpring(value: wrappedValue, duration: duration, bounce: bounce)
    }

    /// Add an impulse: throw the value without moving the target, and it
    /// springs back.
    public func kick(_ impulse: Value) {
        spring.kick(impulse)
    }

    /// Jump straight to `value` at rest, with no animation.
    public func set(_ value: Value) {
        spring.set(value)
    }

    /// Advance the spring by `dt` seconds. Called by the sketch each frame.
    package func advance(by dt: Double) {
        spring.advance(by: dt)
    }
}
