import Foundation
import os

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
///
/// Every named curve carries its name, so a curve is a value you can compare,
/// persist, and pick from a menu: `@Param var curve: Easing = .easeInOut` gets
/// an inspector row like any other parameter. Two closures cannot be compared, so a
/// curve built from one takes a serial of its own instead: it equals itself
/// (and every copy of itself) and nothing else.
public struct Easing: Sendable, Equatable {
    /// The shaping function. Receives progress already clamped to `0...1`.
    public let curve: @Sendable (Double) -> Double

    /// What tells one curve from another.
    private indirect enum Identity: Equatable, Sendable {
        case named(String)
        case custom(UInt64)
        /// A curve derived from another by `reversed()` or `mirrored()`: the
        /// operation's name over the origin's identity, so deriving the same
        /// thing twice gives equal values.
        case derived(String, from: Identity)

        /// A built-in's name, a derivation's path over it, `nil` under a closure.
        var name: String? {
            switch self {
            case .named(let name): return name
            case .custom: return nil
            case .derived(let operation, let origin): return origin.name.map { "\($0).\(operation)" }
            }
        }
    }
    private let identity: Identity

    /// Hands out one serial per curve built from a closure.
    private static let serials = OSAllocatedUnfairLock(initialState: UInt64(0))

    public init(_ curve: @escaping @Sendable (Double) -> Double) {
        self.curve = curve
        self.identity = .custom(Easing.serials.withLock { serial in
            serial += 1
            return serial
        })
    }

    /// A built-in curve, which carries its name as its identity. The name is
    /// also the key the inspector menu persists, so it must stay stable.
    private init(_ name: String, _ curve: @escaping @Sendable (Double) -> Double) {
        self.curve = curve
        self.identity = .named(name)
    }

    /// The name of a built-in curve, or `nil` for one built from a closure. A
    /// curve derived from a built-in reads as a path (`easeOutQuad.mirrored`).
    var name: String? { identity.name }

    public static func == (lhs: Easing, rhs: Easing) -> Bool {
        lhs.identity == rhs.identity
    }

    /// Shape `t` through the curve. The input `t` is clamped to `0...1` first, so
    /// values past the ends hold flat. The *output* is not clamped: the back,
    /// elastic, and bounce curves overshoot `0...1` mid-flight on purpose, then
    /// settle exactly on the endpoints.
    public func callAsFunction(_ t: Double) -> Double {
        curve(Swift.min(Swift.max(t, 0), 1))
    }

    // MARK: Deriving one curve from another

    /// The same curve run from its other end, `1 - curve(1 - t)`: an ease-in
    /// becomes its ease-out, an ease-out its ease-in, and a symmetric curve
    /// (every ease-in-out, `linear`, `smoothstep`) comes back unchanged. The
    /// catalog's ease-outs are exactly the reflected ease-ins, so reversing a
    /// built-in hands back the built-in on the other side of its family:
    /// `Easing.easeInQuad.reversed() == .easeOutQuad`. Any other curve gets the
    /// reflection itself, which compares equal to another reversal of the same
    /// curve and to nothing else.
    public func reversed() -> Easing {
        if let partner = catalogPartner { return partner }
        let curve = self.curve
        return Easing(.derived("reversed", from: identity)) { t in 1 - curve(1 - t) }
    }

    /// The curve on the first half of the trip and its reverse on the second,
    /// squeezed into one span: `curve(2t) / 2` up to the middle, then
    /// `1 - curve(2 - 2t) / 2`. That is how the catalog builds an ease-in-out
    /// from an ease-in, so `Easing.easeInQuad.mirrored() == .easeInOutQuad`,
    /// and the same holds for the sine, cubic, quartic, quintic, exponential,
    /// circular, and bounce families. The back and elastic families are the
    /// exception: their ease-in-outs were tuned with their own constants, so
    /// mirroring `easeInBack` gives the plain construction, a curve of its own.
    /// Mirroring an ease-out gives an out-in curve, fast at both ends and slow
    /// through the middle, which the catalog does not carry.
    public func mirrored() -> Easing {
        if let inOut = catalogInOut { return inOut }
        let curve = self.curve
        return Easing(.derived("mirrored", from: identity)) { t in
            t < 0.5 ? curve(2 * t) / 2 : 1 - curve(2 - 2 * t) / 2
        }
    }

    /// The built-in on the other side of this built-in's family, if the
    /// receiver is one: `easeInX` for `easeOutX` and back, and a symmetric
    /// curve for itself. `nil` for any curve not in the catalog.
    private var catalogPartner: Easing? {
        guard case .named(let name) = identity else { return nil }
        let partnerName: String
        if name.hasPrefix("easeInOut") || name == "linear" || name == "smoothstep" {
            return self
        } else if name.hasPrefix("easeIn") {
            partnerName = "easeOut" + name.dropFirst("easeIn".count)
        } else if name.hasPrefix("easeOut") {
            partnerName = "easeIn" + name.dropFirst("easeOut".count)
        } else {
            return nil
        }
        return Easing.all.first { $0.name == partnerName }?.value
    }

    /// The built-in ease-in-out for this built-in ease-in, when the catalog's
    /// one is exactly the mirrored construction. Back and elastic are not: their
    /// ease-in-outs carry their own constants, so they stay off this list and
    /// `mirrored()` builds the curve instead.
    private var catalogInOut: Easing? {
        guard case .named(let name) = identity, name.hasPrefix("easeIn"),
              !name.hasPrefix("easeInOut") else { return nil }
        let family = name.dropFirst("easeIn".count)
        guard Easing.mirroredFamilies.contains(String(family)) else { return nil }
        return Easing.all.first { $0.name == "easeInOut" + family }?.value
    }

    /// The families whose ease-in-out is the mirrored ease-in to the last digit.
    private static let mirroredFamilies: Set<String> = [
        "Sine", "Quad", "Cubic", "Quart", "Quint", "Expo", "Circ", "Bounce",
    ]

    /// A derived curve, carrying the identity it was derived under.
    private init(_ identity: Identity, _ curve: @escaping @Sendable (Double) -> Double) {
        self.curve = curve
        self.identity = identity
    }

    /// Constant speed, no easing.
    public static let linear = Easing("linear") { $0 }

    // MARK: Sine

    public static let easeInSine = Easing("easeInSine") { 1 - cos(($0 * .pi) / 2) }
    public static let easeOutSine = Easing("easeOutSine") { sin(($0 * .pi) / 2) }
    public static let easeInOutSine = Easing("easeInOutSine") { -(cos(.pi * $0) - 1) / 2 }

    // MARK: Quadratic

    public static let easeInQuad = Easing("easeInQuad") { $0 * $0 }
    public static let easeOutQuad = Easing("easeOutQuad") { 1 - (1 - $0) * (1 - $0) }
    public static let easeInOutQuad = Easing("easeInOutQuad") { t in
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }

    // MARK: Cubic

    public static let easeInCubic = Easing("easeInCubic") { $0 * $0 * $0 }
    public static let easeOutCubic = Easing("easeOutCubic") { 1 - pow(1 - $0, 3) }
    public static let easeInOutCubic = Easing("easeInOutCubic") { t in
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    // MARK: Quartic

    public static let easeInQuart = Easing("easeInQuart") { $0 * $0 * $0 * $0 }
    public static let easeOutQuart = Easing("easeOutQuart") { 1 - pow(1 - $0, 4) }
    public static let easeInOutQuart = Easing("easeInOutQuart") { t in
        t < 0.5 ? 8 * t * t * t * t : 1 - pow(-2 * t + 2, 4) / 2
    }

    // MARK: Quintic

    public static let easeInQuint = Easing("easeInQuint") { pow($0, 5) }
    public static let easeOutQuint = Easing("easeOutQuint") { 1 - pow(1 - $0, 5) }
    public static let easeInOutQuint = Easing("easeInOutQuint") { t in
        t < 0.5 ? 16 * pow(t, 5) : 1 - pow(-2 * t + 2, 5) / 2
    }

    // MARK: Exponential

    public static let easeInExpo = Easing("easeInExpo") { t in
        t == 0 ? 0 : pow(2, 10 * t - 10)
    }
    public static let easeOutExpo = Easing("easeOutExpo") { t in
        t == 1 ? 1 : 1 - pow(2, -10 * t)
    }
    public static let easeInOutExpo = Easing("easeInOutExpo") { t in
        if t == 0 { return 0 }
        if t == 1 { return 1 }
        return t < 0.5 ? pow(2, 20 * t - 10) / 2 : (2 - pow(2, -20 * t + 10)) / 2
    }

    // MARK: Circular

    public static let easeInCirc = Easing("easeInCirc") { 1 - sqrt(1 - pow($0, 2)) }
    public static let easeOutCirc = Easing("easeOutCirc") { sqrt(1 - pow($0 - 1, 2)) }
    public static let easeInOutCirc = Easing("easeInOutCirc") { t in
        t < 0.5
            ? (1 - sqrt(1 - pow(2 * t, 2))) / 2
            : (sqrt(1 - pow(-2 * t + 2, 2)) + 1) / 2
    }

    // MARK: Back (overshoots, then settles)

    public static let easeInBack = Easing("easeInBack") { t in
        let c1 = 1.70158, c3 = 1.70158 + 1
        return c3 * t * t * t - c1 * t * t
    }
    public static let easeOutBack = Easing("easeOutBack") { t in
        let c1 = 1.70158, c3 = 1.70158 + 1
        return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
    }
    public static let easeInOutBack = Easing("easeInOutBack") { t in
        let c2 = 1.70158 * 1.525
        return t < 0.5
            ? (pow(2 * t, 2) * ((c2 + 1) * 2 * t - c2)) / 2
            : (pow(2 * t - 2, 2) * ((c2 + 1) * (2 * t - 2) + c2) + 2) / 2
    }

    // MARK: Elastic (springs past, then settles)

    public static let easeInElastic = Easing("easeInElastic") { t in
        if t == 0 { return 0 }
        if t == 1 { return 1 }
        let c4 = (2 * Double.pi) / 3
        return -pow(2, 10 * t - 10) * sin((t * 10 - 10.75) * c4)
    }
    public static let easeOutElastic = Easing("easeOutElastic") { t in
        if t == 0 { return 0 }
        if t == 1 { return 1 }
        let c4 = (2 * Double.pi) / 3
        return pow(2, -10 * t) * sin((t * 10 - 0.75) * c4) + 1
    }
    public static let easeInOutElastic = Easing("easeInOutElastic") { t in
        if t == 0 { return 0 }
        if t == 1 { return 1 }
        let c5 = (2 * Double.pi) / 4.5
        return t < 0.5
            ? -(pow(2, 20 * t - 10) * sin((20 * t - 11.125) * c5)) / 2
            : (pow(2, -20 * t + 10) * sin((20 * t - 11.125) * c5)) / 2 + 1
    }

    // MARK: Bounce

    public static let easeInBounce = Easing("easeInBounce") { 1 - bounceOut(1 - $0) }
    public static let easeOutBounce = Easing("easeOutBounce") { bounceOut($0) }
    public static let easeInOutBounce = Easing("easeInOutBounce") { t in
        t < 0.5
            ? (1 - bounceOut(1 - 2 * t)) / 2
            : (1 + bounceOut(2 * t - 1)) / 2
    }

    // MARK: Aliases & extras

    /// Friendly default for "ease in": cubic.
    public static let easeIn = easeInCubic
    /// Friendly default for "ease out": cubic.
    public static let easeOut = easeOutCubic
    /// Friendly default for "ease in and out": cubic, the classic smooth feel.
    public static let easeInOut = easeInOutCubic
    /// Hermite smoothstep, a gentler S than `easeInOut`. The same curve as the
    /// bare `smoothstep(0, 1, t)`, packaged as an `Easing` for the APIs that
    /// take one.
    public static let smoothstep = Easing("smoothstep") { t in t * t * (3 - 2 * t) }

    /// Every built-in curve, in the order a menu shows them. The three friendly
    /// aliases are the cubic curves themselves, so they are not listed twice:
    /// picking `.easeInOut` reads, and persists, as `easeInOutCubic`.
    static let all: [(name: String, value: Easing)] = [
        ("linear", .linear),
        ("easeInSine", .easeInSine), ("easeOutSine", .easeOutSine),
        ("easeInOutSine", .easeInOutSine),
        ("easeInQuad", .easeInQuad), ("easeOutQuad", .easeOutQuad),
        ("easeInOutQuad", .easeInOutQuad),
        ("easeInCubic", .easeInCubic), ("easeOutCubic", .easeOutCubic),
        ("easeInOutCubic", .easeInOutCubic),
        ("easeInQuart", .easeInQuart), ("easeOutQuart", .easeOutQuart),
        ("easeInOutQuart", .easeInOutQuart),
        ("easeInQuint", .easeInQuint), ("easeOutQuint", .easeOutQuint),
        ("easeInOutQuint", .easeInOutQuint),
        ("easeInExpo", .easeInExpo), ("easeOutExpo", .easeOutExpo),
        ("easeInOutExpo", .easeInOutExpo),
        ("easeInCirc", .easeInCirc), ("easeOutCirc", .easeOutCirc),
        ("easeInOutCirc", .easeInOutCirc),
        ("easeInBack", .easeInBack), ("easeOutBack", .easeOutBack),
        ("easeInOutBack", .easeInOutBack),
        ("easeInElastic", .easeInElastic), ("easeOutElastic", .easeOutElastic),
        ("easeInOutElastic", .easeInOutElastic),
        ("easeInBounce", .easeInBounce), ("easeOutBounce", .easeOutBounce),
        ("easeInOutBounce", .easeInOutBounce),
        ("smoothstep", .smoothstep),
    ]
}

/// A value the sketch advances once per frame with the frame's `deltaTime`:
/// the `@Eased` tween, the `@Smoothed` filter, a `Timeline`, or a satellite's
/// clock-following object (a video player tracking the export clock). The
/// sketch collects conformers from its stored properties via reflection (like
/// `@Param`) once, at the first frame, so a conformer must already be stored
/// (directly or optionally) on the sketch by the end of `setup()`; one created
/// lazily mid-run is never advanced.
package protocol FrameAdvancing: AnyObject {
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
/// The sketch advances it automatically every frame, so motion is the default:
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
/// the target every frame. Only a *change* restarts the tween, from wherever the
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

    /// The eased value itself, via `$x`, which exposes the target and motion state.
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
    package func advance(by dt: Double) {
        guard elapsed < duration, duration > 0 else {
            current = targetValue
            return
        }
        elapsed += dt
        let t = Swift.min(elapsed / duration, 1)
        current = start + (targetValue - start) * curve(t)
    }
}
