import Foundation

/// Wood grain as line work a plotter can draw: streamlines traced through an
/// angle field, so the lines run with the grain, bend around the knots, and
/// bunch up every so often across the grain where a ring is.
///
/// The field is a *ring coordinate*, the distance across the grain lifted by
/// a Gaussian bump at every knot and wandered by two octaves of noise. Each
/// stroke is a level curve of that coordinate, so it never crosses another,
/// it closes into a loop where it circles a knot, and the ring it belongs to
/// is the same along its whole length: its `tone`, 1 on the darkest ring and
/// 0 on the light wood between rings. The rings show twice, as the tone and
/// as density: `trace` spaces the strokes `spacing` apart on a ring and up to
/// three times that between rings (`ringContrast`), the way the lines of a
/// plotted plank crowd at every ring.
///
/// Strokes are ordinary point lists, so they feed stroking, the shape
/// booleans, hatching, and the vector exports. Trace once and hold the result;
/// the same seed traces the same strokes.
///
/// ```swift
/// let plank = WoodGrain.trace(in: canvasRectangle, direction: 0.15, spacing: 6, knots: 2, seed: 3)
/// noFill(); strokeCap(.round)
/// for line in plank.strokes {
///     stroke(Color(hex: 0x4A2E1A).withAlpha(0.35 + 0.65 * line.tone))
///     if line.isClosed { drawPolygon(line.points) } else { drawPolyline(line.points) }
/// }
/// ```
public struct WoodGrain: Equatable, Sendable {

    /// A knot: a bump in the ring coordinate that the grain flows around.
    public struct Knot: Equatable, Sendable {
        /// Where the knot's eye is.
        public let center: Vector2
        /// How far the knot bends the grain: the width of its Gaussian.
        public let radius: Double
        /// The bump's height in radii. Past about 1.65 the rings close into
        /// loops around the knot; below it they only bend past it.
        public let height: Double

        public init(center: Vector2, radius: Double, height: Double = 3) {
            self.center = center
            self.radius = max(radius, 1e-6)
            self.height = height
        }

        /// The height above which rings close around a knot: a bump steeper
        /// than the grain's own slope somewhere on its flank.
        public static let closingHeight = exp(0.5)

        /// `count` knots thrown over `region` from a seed, each a twentieth
        /// to a tenth of the region's shorter side across, kept well apart
        /// and clear of the edges; a crowded region takes fewer than asked.
        public static func scatter(in region: Rectangle, count: Int, seed: Int = 0) -> [Knot] {
            var rng = SplitMix64(seed: UInt64(bitPattern: Int64(seed)) &+ 0x9E37_79B9_7F4A_7C15)
            let short = min(region.width, region.height)
            var knots: [Knot] = []
            var tries = 0
            while knots.count < count, tries < max(count, 1) * 60 {
                tries += 1
                let radius = short * Double.random(in: 0.05 ... 0.1, using: &rng)
                let inset = radius * 2.5
                guard region.width > inset * 2, region.height > inset * 2 else { break }
                let center = Vector2(Double.random(in: (region.x + inset) ... (region.x + region.width - inset), using: &rng),
                                     Double.random(in: (region.y + inset) ... (region.y + region.height - inset), using: &rng))
                let height = Double.random(in: 2.6 ... 4, using: &rng)
                if knots.allSatisfy({ ($0.center - center).length > ($0.radius + radius) * 3.5 }) {
                    knots.append(Knot(center: center, radius: radius, height: height))
                }
            }
            return knots
        }
    }

    /// One stroke of the grain: a level curve of the ring coordinate.
    public struct Stroke: Equatable, Sendable {
        /// The points along the stroke.
        public let points: [Vector2]
        /// The ring the stroke sits on, 0 the light wood between rings and 1
        /// the darkest ring, the same along the whole stroke.
        public let tone: Double
        /// Whether the stroke closed on itself, a ring around a knot: draw it
        /// as a polygon rather than a polyline.
        public let isClosed: Bool

        public init(points: [Vector2], tone: Double, isClosed: Bool = false) {
            self.points = points
            self.tone = min(max(tone, 0), 1)
            self.isClosed = isClosed
        }
    }

    /// The strokes, in the order they were traced.
    public let strokes: [Stroke]
    /// The knots the grain flows around.
    public let knots: [Knot]
    /// The grain's direction in radians, 0 along x.
    public let direction: Double
    /// The distance across the grain from one ring to the next.
    public let ringSpacing: Double
    /// How far the grain wanders, as a fraction of the ring spacing. Past
    /// about 0.5 the wander can pinch a stroke off into an island.
    public let wobble: Double
    /// The seed the wander and the rings' unevenness were drawn from.
    public let seed: Int

    public init(strokes: [Stroke], knots: [Knot], direction: Double = 0, ringSpacing: Double = 48,
                wobble: Double = 0.35, seed: Int = 0) {
        self.strokes = strokes
        self.knots = knots
        self.direction = direction
        self.ringSpacing = max(ringSpacing, 1e-6)
        self.wobble = max(wobble, 0)
        self.seed = seed
    }

    /// Every stroke's points, for a loop that only strokes.
    public var lines: [[Vector2]] { strokes.map(\.points) }

    /// The ring coordinate at a point: the distance across the grain, lifted
    /// by the knots and wandered by the wobble. Every stroke is a level curve
    /// of it, so it reads the same along a stroke, and `ringSpacing` of it is
    /// one ring.
    public func across(_ point: Vector2) -> Double {
        ruler.value(point)
    }

    /// The ring tone at a point, 0 the light wood between rings and 1 the
    /// darkest ring: what a stroke through it carries as its `tone`.
    public func tone(at point: Vector2) -> Double {
        ruler.tone(ruler.value(point))
    }

    /// The angle field the strokes follow: along the grain, turning around
    /// the knots, perpendicular to the ring coordinate's slope at every
    /// point. Build it once and hold it; it carries the noise tables.
    public var field: FlowField {
        let ruler = self.ruler
        return FlowField { p in ruler.direction(p).angle }
    }

    private var ruler: Ruler {
        Ruler(direction: direction, knots: knots, ringSpacing: ringSpacing, wobble: wobble, seed: seed)
    }

    // MARK: - Tracing

    /// The grain traced over `region` with `knots` knots thrown from the seed
    /// (`Knot.scatter`), see `trace(in:direction:spacing:knots:ringSpacing:ringContrast:wobble:seed:)`.
    public static func trace(in region: Rectangle, direction: Double = 0, spacing: Double = 6, knots: Int = 2,
                             ringSpacing: Double = 48, ringContrast: Double = 0.6, wobble: Double = 0.35,
                             seed: Int = 0) -> WoodGrain {
        trace(in: region, direction: direction, spacing: spacing,
              knots: Knot.scatter(in: region, count: max(knots, 0), seed: seed),
              ringSpacing: ringSpacing, ringContrast: ringContrast, wobble: wobble, seed: seed)
    }

    /// The grain traced over `region`: evenly spaced streamlines through the
    /// angle field, `spacing` apart on a ring and up to `1 + 2 * ringContrast`
    /// times that between rings, every stroke a level curve of the ring
    /// coordinate (a Newton step after every advance keeps it on its level,
    /// so a stroke around a knot comes back to its start and closes). The
    /// first seeds run across the grain through the region's center, and
    /// every traced stroke seeds the next ones beside it, so the whole region
    /// fills; a seed closer to a stroke than its spacing allows is skipped,
    /// and a stroke stops at half its spacing from another, at the region's
    /// edge, or where it closes. The same seed traces the same strokes.
    ///
    /// - Parameters:
    ///   - region: where the grain is traced; strokes stop at its edge.
    ///   - direction: the grain's direction in radians, 0 along x.
    ///   - spacing: the distance between strokes on a ring.
    ///   - knots: the knots the grain flows around.
    ///   - ringSpacing: the distance across the grain from ring to ring.
    ///   - ringContrast: how much sparser the strokes are between rings, 0
    ///     for even spacing and 1 for three times the spacing.
    ///   - wobble: how far the grain wanders, as a fraction of the ring
    ///     spacing; 0 for straight grain.
    ///   - seed: the wander and the rings' unevenness.
    public static func trace(in region: Rectangle, direction: Double = 0, spacing: Double = 6, knots: [Knot],
                             ringSpacing: Double = 48, ringContrast: Double = 0.6, wobble: Double = 0.35,
                             seed: Int = 0) -> WoodGrain {
        let spacing = max(spacing, 0.5)
        let contrast = min(max(ringContrast, 0), 1)
        let ruler = Ruler(direction: direction, knots: knots, ringSpacing: ringSpacing, wobble: wobble, seed: seed)
        let maxSeparation = spacing * (1 + 2 * contrast)
        let step = max(0.75, min(spacing * 0.45, 4))
        let maxSteps = Int((region.width + region.height) * 2.5 / step) + 16
        var index = SpatialIndex(bounds: region, cellSize: maxSeparation)

        func separation(_ p: Vector2) -> Double {
            spacing * (1 + 2 * contrast * (1 - ruler.tone(ruler.value(p))))
        }

        /// One side of a stroke from `start` along its level, ending at the
        /// region's edge, near another stroke, or back at the start.
        func march(from start: Vector2, level: Double, sign: Double) -> (points: [Vector2], closed: Bool) {
            var points = [start]
            var p = start
            for i in 0 ..< maxSteps {
                var next = p + ruler.direction(p) * (step * sign)
                let g = ruler.gradient(next)
                let g2 = g.lengthSquared
                guard g2 > 1e-9 else { break }
                let pull = (ruler.value(next) - level) / g2
                let correction = g * pull
                next -= correction.length > step ? correction.normalized * step : correction
                guard region.contains(next) else { break }
                if i >= 8, sign > 0, (next - start).length < step * 0.6 { return (points, true) }
                if index.hasNeighbor(of: next, within: 0.5 * separation(next)) { break }
                points.append(next)
                p = next
            }
            return (points, false)
        }

        var queue: [(seed: Vector2, spawn: Double)] = []
        let center = region.center
        let reach = region.width + region.height
        var t = -reach
        while t <= reach {
            let p = center + ruler.acrossAxis * t
            if region.contains(p) { queue.append((p, spacing)) }
            t += spacing
        }

        var strokes: [Stroke] = []
        var head = 0
        let stride = max(1, Int(spacing / step))
        while head < queue.count {
            let (seed, spawn) = queue[head]
            head += 1
            guard region.contains(seed) else { continue }
            guard ruler.gradient(seed).lengthSquared > 1e-6 else { continue }   // a knot's eye
            if index.hasNeighbor(of: seed, within: 0.75 * min(spawn, separation(seed))) { continue }
            let level = ruler.value(seed)
            let forward = march(from: seed, level: level, sign: 1)
            let points: [Vector2]
            if forward.closed {
                points = forward.points
            } else {
                let backward = march(from: seed, level: level, sign: -1)
                points = Array(backward.points.dropFirst().reversed()) + forward.points
            }
            guard points.count >= 3 else { continue }
            for p in points { index.insert(p) }
            strokes.append(Stroke(points: points, tone: ruler.tone(level), isClosed: forward.closed))
            var i = 0
            while i < points.count {
                let p = points[i]
                let sep = separation(p)
                let across = ruler.direction(p).perpendicular
                queue.append((p + across * sep, sep))
                queue.append((p - across * sep, sep))
                i += stride
            }
        }
        return WoodGrain(strokes: strokes, knots: knots, direction: direction, ringSpacing: ringSpacing,
                         wobble: wobble, seed: seed)
    }

    // MARK: - The ring coordinate

    /// The ring coordinate and what is read from it, with the noise tables
    /// built once.
    private struct Ruler {
        let along: Vector2
        let acrossAxis: Vector2
        let knots: [Knot]
        let ringSpacing: Double
        let wobble: Double
        let fields: NoiseFields

        init(direction: Double, knots: [Knot], ringSpacing: Double, wobble: Double, seed: Int) {
            along = Vector2(angle: direction)
            acrossAxis = along.perpendicular
            self.knots = knots
            self.ringSpacing = max(ringSpacing, 1e-6)
            self.wobble = max(wobble, 0)
            fields = NoiseFields(seed: seed)
        }

        /// The distance across the grain, lifted by the knots and wandered.
        func value(_ p: Vector2) -> Double {
            var r = p.dot(acrossAxis)
            for knot in knots {
                let d2 = (p - knot.center).lengthSquared
                r += knot.height * knot.radius * exp(-d2 / (2 * knot.radius * knot.radius))
            }
            if wobble > 0 {
                // Eight rings of wavelength along the grain and five across:
                // the wander's slope stays under the grain's own up to a
                // wobble of about 0.5, so the coordinate keeps climbing and
                // no stroke pinches off into an island.
                let u = p.dot(along) / (ringSpacing * 8)
                let v = p.dot(acrossAxis) / (ringSpacing * 5)
                r += wobble * ringSpacing * (fields.fbm(u, v, octaves: 2) - 0.5) * 2
            }
            return r
        }

        func gradient(_ p: Vector2) -> Vector2 {
            let h = 0.5
            return Vector2((value(Vector2(p.x + h, p.y)) - value(Vector2(p.x - h, p.y))) / (2 * h),
                           (value(Vector2(p.x, p.y + h)) - value(Vector2(p.x, p.y - h))) / (2 * h))
        }

        /// The unit tangent of the level curve through `p`, along the grain.
        func direction(_ p: Vector2) -> Vector2 {
            let g = gradient(p)
            let t = Vector2(g.y, -g.x)
            return t.lengthSquared > 1e-12 ? t.normalized : along
        }

        /// The ring tone of a ring coordinate: a narrow dark band every
        /// `ringSpacing`, the rings' positions wandered by a slow noise so
        /// no two rings are the same width.
        func tone(_ r: Double) -> Double {
            let cycles = r / ringSpacing
            let jitter = 0.25 * fields.signedNoise(cycles * 0.5 + 17.3)
            let c = 0.5 + 0.5 * cos((cycles + jitter) * .tau)
            return c * c
        }
    }
}
