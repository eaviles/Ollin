import Foundation

/// How a stroke's width varies along a path. Set it with `strokeProfile(_:)`, the
/// way `strokeCap(_:)` sets the ends; the choice holds until changed, and
/// `noStrokeProfile()` returns to a constant width.
///
/// A profile is a *multiplier*, not a width: `strokeWeight` still sets how fat the
/// mark gets, and the profile says what fraction of that it uses at each point
/// along the path. So a stroke that swells to 12 points in the middle and vanishes
/// at both ends is two calls:
///
/// ```swift
/// strokeWeight(12)
/// strokeProfile(.taper())
/// drawBezier(a, c1, c2, b)
/// ```
///
/// The multiplier is read at every point of the path, from `0` at the start to `1`
/// at the end measured along the path's own length. `.nib` also reads the
/// direction the stroke is heading, which is what makes a flat pen thicken and
/// thin as the path turns.
///
/// It applies wherever a path is expanded into a stroke: `drawLine`, `drawBezier`,
/// `drawPolyline`, `drawCurve`, and the outlines of `drawShape` and `drawPolygon`.
/// The analytic shapes (`drawCircle`, `drawRect`, `drawStar`, and friends) carry a
/// single width by construction, so they keep drawing at `strokeWeight` and note
/// it once.
///
/// Build one from any closure over the path fraction:
///
/// ```swift
/// strokeProfile { t in 0.2 + 0.8 * sin(t * .pi) }
/// ```
public struct StrokeProfile: Sendable {
    /// The width multiplier at path fraction `t` (already clamped to `0...1`) for a
    /// stroke heading `direction` (a unit vector). Negative returns are clamped to
    /// zero at the call site.
    public let multiplier: @Sendable (_ t: Double, _ direction: Vector2) -> Double

    /// True only for `.uniform`, the constant-width default. The stroke expander
    /// and the vector exporter both take their original constant-width path when
    /// this is set, so an unprofiled stroke costs nothing and draws identically.
    let isUniform: Bool

    /// A profile from a closure over the path fraction alone, the common case.
    public init(_ multiplier: @escaping @Sendable (_ t: Double) -> Double) {
        self.multiplier = { t, _ in multiplier(t) }
        self.isUniform = false
    }

    /// A profile that also reads the direction the stroke is heading, for
    /// direction-dependent marks like a flat nib.
    public init(directional multiplier: @escaping @Sendable (_ t: Double, _ direction: Vector2) -> Double) {
        self.multiplier = multiplier
        self.isUniform = false
    }

    private init(uniform: Bool) {
        self.multiplier = { _, _ in 1 }
        self.isUniform = uniform
    }

    /// The width at path fraction `t`, heading `direction`, as a fraction of
    /// `strokeWeight`. `t` is clamped to `0...1` and the result to `0...`.
    public func callAsFunction(_ t: Double, direction: Vector2 = Vector2(1, 0)) -> Double {
        max(0, multiplier(min(max(t, 0), 1), direction))
    }

    /// Constant width for the whole path: the default, and the same geometry the
    /// stroke renderer drew before profiles existed.
    public static let uniform = StrokeProfile(uniform: true)

    /// Thin at the ends, full width in the middle: the shape of a brush pressed
    /// down and lifted again. `start` and `end` are the multipliers *at* the two
    /// ends, so the default tapers to nothing at both; `.taper(start: 1)` keeps a
    /// blunt start and lifts off at the end.
    ///
    /// The rise and fall are smooth, so a thick stroke has no kink at the middle.
    public static func taper(start: Double = 0, end: Double = 0) -> StrokeProfile {
        StrokeProfile { t in
            t < 0.5 ? lerp(start, 1, Easing.smoothstep(t * 2))
                    : lerp(1, end, Easing.smoothstep((t - 0.5) * 2))
        }
    }

    /// A straight wedge: `from` at the start of the path growing to `to` at the
    /// end, both as fractions of `strokeWeight`.
    public static func ramp(from start: Double, to end: Double) -> StrokeProfile {
        StrokeProfile { t in lerp(start, end, t) }
    }

    /// A flat pen nib held at a fixed `angle`. A stroke running along the nib's
    /// edge draws its thinnest line, one running across it draws the full weight,
    /// and everything between interpolates, which is the thick-and-thin contrast of
    /// broad-edge calligraphy. `thinness` is how much width the thinnest direction
    /// keeps (`0` for a nib that disappears edge-on, the default `0.15` for the
    /// hairline a real nib leaves).
    public static func nib(angle: Double, thinness: Double = 0.15) -> StrokeProfile {
        let edge = Vector2(cos(angle), sin(angle))
        let floor = min(max(thinness, 0), 1)
        return StrokeProfile(directional: { _, d in
            // |cross(direction, edge)| is 0 along the nib and 1 across it.
            floor + (1 - floor) * abs(d.x * edge.y - d.y * edge.x)
        })
    }

    /// A profile sampled from evenly spaced multipliers along the path, linearly
    /// interpolated between them: a hand-drawn width curve, or one recorded from an
    /// input. A single value is a constant width; an empty array is full width.
    public static func values(_ values: [Double]) -> StrokeProfile {
        guard let first = values.first else { return StrokeProfile { _ in 1 } }
        guard values.count > 1 else { return StrokeProfile { _ in first } }
        return StrokeProfile { t in
            let x = t * Double(values.count - 1)
            let i = min(Int(x), values.count - 2)
            return lerp(values[i], values[i + 1], x - Double(i))
        }
    }
}
