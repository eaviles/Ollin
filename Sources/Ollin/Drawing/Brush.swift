import Foundation

/// A mark made by repeating one shape along a path, instead of expanding the path
/// into a continuous ribbon. Set it with `strokeBrush(_:)`, the way
/// `strokeProfile(_:)` sets how width varies; the choice holds until changed, and
/// `noStrokeBrush()` returns to the ribbon.
///
/// ```swift
/// strokeWeight(18)
/// strokeBrush(Brush(.circle, spacing: 0.5, scatter: 0.6))
/// drawPolyline(points)
/// ```
///
/// The stamp is sized by `strokeWeight` and painted with the current `stroke`, so
/// a brush is a change of *texture*, not of weight or color. `strokeProfile(_:)`
/// still shapes the size along the path, which is what makes a scattered stroke
/// that thins out at its ends one more call.
///
/// Everything random is a fraction of the stamp's own size, and everything is
/// seeded, so the same path draws the same mark every frame. Animate the path and
/// the stamps travel with it rather than boiling in place, because a stamp's
/// randomness is keyed to its index along the path.
///
/// Not `Sendable` or `Equatable`, because a texture tip carries an `Image` and
/// an image is neither. A brush is drawing state on the main actor like the rest
/// of the style, so neither is missed.
public struct Brush {

    /// What gets stamped.
    public enum Tip {
        /// A filled disc, the plain round brush.
        case circle
        /// A filled square, which turns with `angle`.
        case square
        /// Any shape, drawn at the stamp's size and turned with `angle`. Its own
        /// coordinates are taken relative to its bounding box, so a shape of any
        /// size works as a tip.
        case shape(Shape)
        /// A picture, drawn at the stamp's size and turned with `angle`. The
        /// classic texture brush.
        case image(Image)
    }

    /// Which way a stamp faces.
    public enum Angle: Sendable, Equatable {
        /// Turn with the path, so a flat tip reads like a pen held at an angle.
        case followPath
        /// A fixed angle in radians, the same for every stamp.
        case fixed(Double)
        /// A different angle for every stamp.
        case random
    }

    /// What to stamp.
    public var tip: Tip
    /// How far apart the stamps sit, as a fraction of the stamp's size. `1` sets
    /// them edge to edge; below about `0.25` they read as a continuous mark, and
    /// above `1` they read as beads. Clamped to a small positive minimum, since a
    /// spacing of zero is an infinite number of stamps.
    public var spacing: Double
    /// How much each stamp's size varies, `0` for none and `1` to range from
    /// nothing to double.
    public var sizeJitter: Double
    /// Which way each stamp faces.
    public var angle: Angle
    /// A random turn added on top of `angle`, in radians.
    public var angleJitter: Double
    /// How far each stamp strays off the path, as a fraction of its size,
    /// perpendicular to the direction of travel.
    public var scatter: Double
    /// How many stamps to lay down at each step along the path. Above `1` this is
    /// the classic scatter brush, and it wants `scatter` to be worth having.
    public var count: Int
    /// How much each stamp's opacity varies, `0` for none and `1` to range from
    /// invisible to full.
    public var opacityJitter: Double
    /// Fixes the randomness. The same seed and the same path give the same mark.
    public var seed: Int

    public init(_ tip: Tip = .circle,
                spacing: Double = 0.25,
                sizeJitter: Double = 0,
                angle: Angle = .followPath,
                angleJitter: Double = 0,
                scatter: Double = 0,
                count: Int = 1,
                opacityJitter: Double = 0,
                seed: Int = 0) {
        self.tip = tip
        self.spacing = spacing
        self.sizeJitter = sizeJitter
        self.angle = angle
        self.angleJitter = angleJitter
        self.scatter = scatter
        self.count = count
        self.opacityJitter = opacityJitter
        self.seed = seed
    }

    // MARK: Presets

    /// Round stamps close enough to read as one soft mark.
    public static var round: Brush { Brush(.circle, spacing: 0.2) }

    /// Loose round stamps thrown either side of the path, the classic spray.
    public static func spray(spacing: Double = 0.5, scatter: Double = 1.2,
                             count: Int = 3, seed: Int = 0) -> Brush {
        Brush(.circle, spacing: spacing, sizeJitter: 0.6, scatter: scatter,
              count: count, opacityJitter: 0.5, seed: seed)
    }

    /// Square stamps turning with the path, which reads like a chisel nib.
    public static func chisel(spacing: Double = 0.3, angle: Angle = .followPath) -> Brush {
        Brush(.square, spacing: spacing, angle: angle)
    }

    /// Well-separated stamps at every angle, for confetti and leaf litter.
    public static func scatter(_ tip: Tip = .square, spacing: Double = 1.6,
                               seed: Int = 0) -> Brush {
        Brush(tip, spacing: spacing, sizeJitter: 0.5, angle: .random,
              scatter: 1.5, count: 2, opacityJitter: 0.3, seed: seed)
    }

    // MARK: Placing the stamps

    /// One stamp: where it sits, how wide it is, which way it faces, and how much
    /// of the stroke's opacity it carries.
    struct Stamp {
        var center: Vector2
        var size: Double
        var angle: Double
        var opacity: Double
        /// Distance along the path as a fraction, for reading the ambient width
        /// and opacity profiles.
        var t: Double
    }

    /// Walk `points` at even arc-length intervals and place the stamps.
    ///
    /// Spacing is measured in stamp sizes rather than pixels, so a brush keeps its
    /// texture when `strokeWeight` changes: the same brush at twice the weight
    /// makes the same mark, twice as big. `width(t)` reports the stamp size at a
    /// path fraction, which is where an ambient `strokeProfile` gets folded in, and
    /// it is read at the *previous* stamp to decide the next step, so a tapering
    /// stroke's stamps crowd together as it thins the way a real one does.
    static func stamps(along points: [Vector2], closed: Bool, brush: Brush,
                       width: (Double) -> Double, opacity: (Double) -> Double) -> [Stamp] {
        var path = points
        if closed, let first = path.first { path.append(first) }
        guard path.count >= 2 else {
            // A single point still deserves one stamp, so a tap leaves a mark.
            guard let p = path.first, width(0) > 0 else { return [] }
            return [Stamp(center: p, size: width(0), angle: 0, opacity: opacity(0), t: 0)]
        }

        // Arc length at each vertex, so a fraction along the path is a real
        // distance rather than a vertex count.
        var cumulative = [0.0]
        cumulative.reserveCapacity(path.count)
        for i in 1..<path.count {
            cumulative.append(cumulative[i - 1] + (path[i] - path[i - 1]).length)
        }
        let total = cumulative[path.count - 1]
        guard total > 0 else { return [] }

        /// The point and heading at distance `d` along the path.
        func sample(_ d: Double) -> (point: Vector2, direction: Vector2) {
            var i = 1
            while i < path.count - 1, cumulative[i] < d { i += 1 }
            let segment = cumulative[i] - cumulative[i - 1]
            let f = segment > 1e-12 ? (d - cumulative[i - 1]) / segment : 0
            let a = path[i - 1], b = path[i]
            let delta = b - a
            let length = delta.length
            return (a + delta * min(max(f, 0), 1),
                    length > 1e-12 ? delta / length : Vector2(1, 0))
        }

        let step = max(brush.spacing, 0.02)
        let perStep = max(brush.count, 1)
        var stamps: [Stamp] = []
        var traveled = 0.0
        var index = 0
        // A stamp cannot be smaller than this and still be worth placing, and the
        // floor also stops a profile that tapers to nothing from stepping by zero.
        let minimumSize = 0.05

        while traveled <= total {
            let t = traveled / total
            let base = max(width(t), 0)
            let (point, direction) = sample(traveled)
            if base >= minimumSize {
                let alpha = opacity(t)
                for k in 0..<perStep {
                    var random = SplitMix(seed: UInt64(bitPattern: Int64(brush.seed &* 0x9E37_79B9))
                                          &+ UInt64(index &* 4 &+ k) &* 0x85EB_CA6B)
                    var size = base
                    if brush.sizeJitter > 0 {
                        size *= 1 + brush.sizeJitter * (random.unit() * 2 - 1)
                    }
                    var center = point
                    if brush.scatter > 0 {
                        let across = Vector2(-direction.y, direction.x)
                        center = center + across * (brush.scatter * base * (random.unit() * 2 - 1))
                    }
                    var facing: Double
                    switch brush.angle {
                    case .followPath: facing = atan2(direction.y, direction.x)
                    case .fixed(let a): facing = a
                    case .random: facing = random.unit() * .tau
                    }
                    if brush.angleJitter > 0 {
                        facing += brush.angleJitter * (random.unit() * 2 - 1)
                    }
                    var alphaHere = alpha
                    if brush.opacityJitter > 0 {
                        alphaHere *= 1 - brush.opacityJitter * random.unit()
                    }
                    if size > minimumSize, alphaHere > 0.001 {
                        stamps.append(Stamp(center: center, size: size, angle: facing,
                                            opacity: alphaHere, t: t))
                    }
                }
            }
            index += 1
            traveled += max(base, minimumSize) * step
        }
        return stamps
    }
}

/// A tiny seeded generator, so a stamp's randomness is a pure function of its
/// index and the brush's seed. It never touches the sketch's own `random`, the
/// same rule the low-discrepancy samplers follow: a brush must not consume rolls
/// a sketch is counting on elsewhere.
struct SplitMix {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A value in `0..<1`.
    mutating func unit() -> Double { Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0) }
}
