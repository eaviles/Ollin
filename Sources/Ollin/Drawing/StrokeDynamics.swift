import Foundation

/// What was measured at one point of a mark, as the mark was being made. A
/// `StrokeResponse` reads this and answers with a multiplier.
///
/// This is the difference between dynamics and `StrokeProfile`. A profile knows
/// the whole path and asks "where am I along it"; dynamics only knows what has
/// happened so far, because the rest of the mark has not been drawn yet.
public struct StrokeInput: Sendable {
    /// How fast the mark was moving, in canvas points per second, smoothed.
    /// Roughly `200` for a careful hand and past `1500` for a flick across a
    /// 1080-point canvas.
    public var speed: Double
    /// How hard the input was pressed, `0` to `1`, smoothed. See
    /// `Sketch.pressure`: a device that cannot measure pressure reports `1`.
    public var pressure: Double
    /// The unit direction the mark was heading, for dynamics that care which way
    /// the hand moved (a flat pen, a directional wash).
    public var direction: Vector2
    /// How far the mark had traveled to reach this point, in canvas points. `0`
    /// at the first point and growing from there. It is a distance, not a
    /// fraction, precisely because a mark in progress has no known length.
    public var distance: Double

    public init(speed: Double = 0, pressure: Double = 1,
                direction: Vector2 = Vector2(1, 0), distance: Double = 0) {
        self.speed = speed
        self.pressure = pressure
        self.direction = direction
        self.distance = distance
    }
}

/// How one axis of a mark answers to the hand making it: a multiplier for each
/// recorded point, read from what was measured there.
///
/// Width and opacity each take their own, so a brush can be spelled out one axis
/// at a time and nothing is driven by accident:
///
/// ```swift
/// StrokeDynamics(width: .pressure(light: 0.1),      // press for a fat mark
///                opacity: .speed(fast: 0.4))        // hurry for a faint one
/// ```
///
/// A response left out is `.unchanged`, so that axis keeps the stroke's own
/// setting. For anything the named forms do not cover, write the closure; it is
/// handed the whole `StrokeInput`.
public struct StrokeResponse: Sendable {
    /// The multiplier for one measured point.
    public let value: @Sendable (StrokeInput) -> Double

    /// True only for `.unchanged`, the neutral response. When both of a mark's
    /// axes are neutral it records a plain constant stroke and draws exactly
    /// like the polyline it is.
    let isNeutral: Bool

    /// A response from a closure over everything measured at the point.
    public init(_ value: @escaping @Sendable (StrokeInput) -> Double) {
        self.value = value
        self.isNeutral = false
    }

    private init(neutral: Bool) {
        self.value = { _ in 1 }
        self.isNeutral = neutral
    }

    /// This axis is not driven: it keeps the stroke's own weight or alpha.
    public static let unchanged = StrokeResponse(neutral: true)

    /// Driven by how fast the mark is moving, which is the driver that works on
    /// any device.
    ///
    /// `slow` is the multiplier at rest and `fast` the multiplier at `reference`
    /// points per second and beyond, interpolated linearly in between. Passing a
    /// `fast` larger than `slow` reverses the mapping, for a mark that swells as
    /// it speeds up.
    ///
    /// `reference` is in canvas points per second, so it scales with the canvas:
    /// on a much larger or smaller one, pass `1200 * scale`.
    public static func speed(reference: Double = 1200,
                             slow: Double = 1, fast: Double) -> StrokeResponse {
        let invReference = 1 / max(reference, 1e-6)
        return StrokeResponse { lerp(slow, fast, min(max($0.speed * invReference, 0), 1)) }
    }

    /// Driven by how hard the input is pressed: `light` at the faintest touch,
    /// `heavy` at full force.
    ///
    /// This needs a device that measures pressure (a Force Touch trackpad, a pen
    /// tablet). One that cannot reports full force throughout, so a mark comes
    /// out at `heavy` all the way rather than not drawing at all. Read
    /// `Sketch.pressureIsAvailable` to fall back to `.speed(...)` when there is
    /// nothing to feel.
    public static func pressure(light: Double, heavy: Double = 1) -> StrokeResponse {
        StrokeResponse { lerp(light, heavy, min(max($0.pressure, 0), 1)) }
    }
}

/// How a mark's width and opacity answer to the way it is being made. Where
/// `StrokeProfile` shapes a stroke by *where you are* along the path, dynamics
/// shapes it by *how you got there*: fast strokes thin out, a heavy press swells
/// and darkens.
///
/// A `StrokeMark` carries the dynamics that made it, so the usual spelling is
/// one argument:
///
/// ```swift
/// var mark = StrokeMark(.speed(fast: 0.15))
/// ```
///
/// That shorthand drives width only. Drive both, or drive them from different
/// things, by naming each axis:
///
/// ```swift
/// StrokeMark(StrokeDynamics(width: .speed(fast: 0.15),
///                           opacity: .speed(fast: 0.4)))
/// ```
///
/// Both axes are multipliers, matching `StrokeProfile`: width scales
/// `strokeWeight` and opacity scales the stroke color's own alpha, so `1` is "as
/// set" on either.
///
/// Like a profile closure, a response runs where the stroke is expanded rather
/// than inside `draw()`, so it is `@Sendable` and cannot capture `time` or a
/// `@Param`. Everything it needs is already in the `StrokeInput`, and the named
/// forms take their shaping as arguments.
public struct StrokeDynamics: Sendable {
    /// How the width multiplier on `strokeWeight` is driven. Clamped to `0...`.
    public let width: StrokeResponse
    /// How the opacity multiplier on the stroke color's alpha is driven. Clamped
    /// to `0...1`.
    public let opacity: StrokeResponse

    /// Whether this brush asks for nothing at all, on either axis.
    var isUniform: Bool { width.isNeutral && opacity.isNeutral }

    /// Dynamics from one response per axis. An axis left out keeps the stroke's
    /// own setting, so `StrokeDynamics()` is `.uniform`.
    public init(width: StrokeResponse = .unchanged, opacity: StrokeResponse = .unchanged) {
        self.width = width
        self.opacity = opacity
    }

    /// Both multipliers for `input`, each clamped to the range it promises. This
    /// is what `StrokeMark` calls for every point it records.
    public func multipliers(for input: StrokeInput) -> (width: Double, opacity: Double) {
        (max(0, width.value(input)), min(max(opacity.value(input), 0), 1))
    }

    /// No dynamics: every point of the mark takes the stroke's own weight and
    /// alpha. A mark recorded with this is a plain polyline that happens to
    /// remember how it was drawn.
    public static let uniform = StrokeDynamics()

    /// The everyday speed brush: a hurried stroke thins to `fast` while its
    /// opacity is left alone. To fade it as well, name both axes on the full
    /// initializer.
    public static func speed(reference: Double = 1200, fast: Double = 0.1) -> StrokeDynamics {
        StrokeDynamics(width: .speed(reference: reference, fast: fast))
    }

    /// The everyday pressure brush: a light touch thins to `light` and a full
    /// press draws at the stroke's own weight. Opacity is left alone.
    public static func pressure(light: Double = 0.1) -> StrokeDynamics {
        StrokeDynamics(width: .pressure(light: light))
    }
}
