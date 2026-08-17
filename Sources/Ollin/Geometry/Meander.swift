import Foundation

/// Meandering: a river centerline that migrates sideways over time, growing
/// bends, cutting them off into oxbow lakes, and leaving scars where it used
/// to run. Each step every point drifts perpendicular to the line, pushed by
/// the curvature at that point and, more strongly, by the curvature a little
/// way upstream, which is what makes bends both deepen and travel downstream.
///
/// The mechanism, per step:
///
/// - **Curvature** is measured along the line; a point's nominal drift is
///   proportional to it (a straight reach does not move).
/// - **Upstream memory**: the drift actually applied blends the local value
///   with an exponentially weighted average of the values upstream, over a
///   distance of about `memoryLength`. The local term enters with a *negative*
///   weight and the upstream average with a larger positive one, so a bend is
///   pushed mostly by the water that entered it, and the whole train of bends
///   slides downstream as it grows.
/// - **Cutoff**: when two reaches of the river come within `cutoffDistance`
///   of each other, the loop between them is cut off into an `Oxbow` and the
///   channel reconnects on the short path. Oxbows shrink each step and are
///   deleted once smaller than the channel width.
/// - **Resample**: the line is redrawn through an interpolating spline at an
///   even `spacing`, so points neither bunch on the outside of a bend nor
///   starve the inside.
///
/// Like the other stateful steppers, you hold one and advance it each frame,
/// and the product is geometry: `centerline` (or `contour`) is the river now,
/// `oxbows` are the lakes it has abandoned, and `scars` (recorded every
/// `recordEvery` steps) are where it ran before, ready for stroking, filling,
/// hatching, and SVG export. Seeded, so the same seed runs the same river.
///
/// ```swift
/// // Held across frames, seeded once:
/// let river = Meander.line(from: Vector2(-60, 540), to: Vector2(1140, 540),
///                          seed: 7, width: 24)
///
/// // In draw():
/// river.step()
/// noFill(); stroke(Color(hex: 0x2C4A6E)); strokeWeight(8)
/// drawPolyline(river.centerline)
/// for oxbow in river.oxbows { drawPolyline(oxbow.points, closed: true) }
/// ```
public final class Meander {
    /// A loop the river has cut off: a crescent lake beside the channel. It
    /// shrinks a little every step and is removed once smaller than the
    /// channel width.
    public struct Oxbow {
        /// The cut-off loop, in path order (stroked at channel width, it
        /// reads as a crescent lake along the old channel).
        public var points: [Vector2]
        /// Steps since the cutoff happened.
        public var age: Int
    }

    /// The river's current centerline, in flow order (index 0 is upstream).
    public private(set) var centerline: [Vector2]
    /// The lakes cut off so far, oldest first.
    public private(set) var oxbows: [Oxbow] = []
    /// Past centerlines, recorded every `recordEvery` steps (empty when 0).
    public private(set) var scars: [[Vector2]] = []

    /// The channel width, the length scale the other defaults hang off.
    public var width: Double
    /// How far a point drifts per step when `width` times curvature is 1.
    public var migrationRate: Double
    /// The distance upstream over which curvature still influences a point;
    /// the weight decays exponentially with distance.
    public var memoryLength: Double
    /// The even spacing the centerline is resampled to after each step.
    public var spacing: Double
    /// Two reaches closer than this (measured across the land, not along the
    /// river) trigger a cutoff.
    public var cutoffDistance: Double
    /// How many points at each end are pinned and never migrate.
    public var fixedEnds: Int
    /// The fraction of its size an oxbow loses per step (toward its center).
    public var oxbowShrink: Double
    /// Record the centerline into `scars` every this many steps (0 = never).
    public var recordEvery: Int
    /// A ceiling on recorded scars; the oldest is dropped past it.
    public var maxScars: Int

    private var rng: SplitMix64
    private var stepsTaken = 0

    /// The local drift enters negatively and the upstream average with this
    /// larger positive weight; together they make bends grow *and* travel.
    private static let localWeight = -1.0
    private static let upstreamWeight = 2.5
    /// Displacement per step is clamped to this fraction of `spacing`, so a
    /// sharp bend cannot step over its own resample resolution.
    private static let maxStepFraction = 0.9

    /// A meander stepper seeded with an initial centerline.
    ///
    /// - Parameters:
    ///   - centerline: The starting path, in flow order (at least four points).
    ///   - seed: The random seed; the same seed runs the same river.
    ///   - width: The channel width, in canvas units.
    ///   - migrationRate: Drift per step at unit `width` times curvature
    ///     (default `width / 4`).
    ///   - memoryLength: The upstream influence distance (default `width * 1.5`).
    ///   - spacing: The resample spacing (default `width / 4`).
    ///   - cutoffDistance: The across-land distance that triggers a cutoff
    ///     (default `width * 2`).
    ///   - fixedEnds: Points pinned at each end (default 3).
    ///   - oxbowShrink: Fraction of its size an oxbow loses per step.
    ///   - recordEvery: Steps between `scars` records (0 = never).
    ///   - maxScars: The scar-count ceiling.
    public init(centerline: [Vector2],
                seed: UInt64 = 0,
                width: Double = 24,
                migrationRate: Double? = nil,
                memoryLength: Double? = nil,
                spacing: Double? = nil,
                cutoffDistance: Double? = nil,
                fixedEnds: Int = 3,
                oxbowShrink: Double = 0.008,
                recordEvery: Int = 0,
                maxScars: Int = 120) {
        self.centerline = centerline
        self.rng = SplitMix64(seed: seed)
        self.width = width
        self.migrationRate = migrationRate ?? width / 4
        self.memoryLength = memoryLength ?? width * 1.5
        self.spacing = spacing ?? width / 4
        self.cutoffDistance = cutoffDistance ?? width * 2
        self.fixedEnds = fixedEnds
        self.oxbowShrink = oxbowShrink
        self.recordEvery = recordEvery
        self.maxScars = maxScars
    }

    /// The number of points currently on the centerline.
    public var count: Int { centerline.count }

    /// The current centerline as an open `Contour`.
    public var contour: Contour { Contour(centerline, closed: false) }

    /// The river's length along the water divided by the straight distance
    /// between its ends: 1 for a straight channel, growing as bends deepen.
    public var sinuosity: Double {
        guard centerline.count >= 2 else { return 1 }
        var along = 0.0
        for i in 1 ..< centerline.count {
            along += centerline[i].distance(to: centerline[i - 1])
        }
        let across = centerline[0].distance(to: centerline[centerline.count - 1])
        return across > 1e-9 ? along / across : 1
    }

    /// Advance the river by one step: migrate every point by the weighted
    /// curvature, cut off any loop that pinches shut, resample the centerline
    /// to an even spacing, then age and shrink the oxbows.
    public func step() {
        stepsTaken += 1
        migrate()
        cutOffLoops()
        centerline = Self.resampledThroughSpline(centerline, spacing: spacing)
        ageOxbows()
        if recordEvery > 0, stepsTaken % recordEvery == 0 {
            scars.append(centerline)
            let ceiling = Swift.max(maxScars, 0)
            if scars.count > ceiling { scars.removeFirst(scars.count - ceiling) }
        }
    }

    /// Advance the river by `steps` steps.
    public func step(_ steps: Int) {
        for _ in 0 ..< Swift.max(steps, 0) { step() }
    }

    // MARK: - Migration

    /// Move each point perpendicular to the line by the curvature-driven rate:
    /// the local term (negative weight) plus the exponentially weighted
    /// average of the rates upstream.
    private func migrate() {
        let n = centerline.count
        guard n >= 4 else { return }

        // Central differences along the index; one-sided at the ends.
        var dx = [Double](repeating: 0, count: n)
        var dy = [Double](repeating: 0, count: n)
        for i in 0 ..< n {
            let a = centerline[Swift.max(i - 1, 0)]
            let b = centerline[Swift.min(i + 1, n - 1)]
            let span = Double(Swift.min(i + 1, n - 1) - Swift.max(i - 1, 0))
            dx[i] = (b.x - a.x) / span
            dy[i] = (b.y - a.y) / span
        }
        var ddx = [Double](repeating: 0, count: n)
        var ddy = [Double](repeating: 0, count: n)
        for i in 0 ..< n {
            let lo = Swift.max(i - 1, 0), hi = Swift.min(i + 1, n - 1)
            let span = Double(hi - lo)
            ddx[i] = (dx[hi] - dx[lo]) / span
            ddy[i] = (dy[hi] - dy[lo]) / span
        }

        // Nominal rate: width times curvature, scaled by the migration rate.
        // The curvature formula is parameterization-invariant, so the
        // index-space derivatives above are fine as long as spacing is even.
        var nominal = [Double](repeating: 0, count: n)
        for i in 0 ..< n {
            let g2 = dx[i] * dx[i] + dy[i] * dy[i]
            guard g2 > 1e-12 else { continue }
            let curvature = (dx[i] * ddy[i] - dy[i] * ddx[i]) / pow(g2, 1.5)
            nominal[i] = migrationRate * width * curvature
        }

        var segment = [Double](repeating: 0, count: n)  // segment[i] = |p[i] - p[i-1]|
        for i in 1 ..< n {
            segment[i] = centerline[i].distance(to: centerline[i - 1])
        }

        // The applied rate: local term plus the normalized upstream average,
        // its weight decaying as exp(-distance / memoryLength). The sum walks
        // upstream and stops once the weight is negligible.
        let memory = Swift.max(memoryLength, 1e-6)
        var applied = [Double](repeating: 0, count: n)
        for i in 0 ..< n {
            var weighted = nominal[i]
            var totalWeight = 1.0
            var distanceBack = 0.0
            var j = i
            while j > 0 {
                distanceBack += segment[j]
                let weight = exp(-distanceBack / memory)
                if weight < 1e-4 { break }
                j -= 1
                weighted += nominal[j] * weight
                totalWeight += weight
            }
            applied[i] = Self.localWeight * nominal[i]
                + Self.upstreamWeight * weighted / totalWeight
        }

        // Clamp the largest step to a fraction of the resample spacing.
        var largest = 0.0
        for i in 0 ..< n { largest = Swift.max(largest, abs(applied[i])) }
        let limit = Self.maxStepFraction * spacing
        let scale = largest > limit ? limit / largest : 1.0

        // Drift perpendicular to the local tangent; pinned ends stay put.
        let pinned = Swift.max(fixedEnds, 0)
        guard n - pinned > pinned else { return }
        for i in pinned ..< (n - pinned) {
            let length = (dx[i] * dx[i] + dy[i] * dy[i]).squareRoot()
            guard length > 1e-9 else { continue }
            let drift = applied[i] * scale / length
            centerline[i] = Vector2(centerline[i].x + drift * dy[i],
                                    centerline[i].y - drift * dx[i])
        }
    }

    // MARK: - Cutoffs

    /// Find two reaches that have pinched within `cutoffDistance` of each
    /// other, cut the loop between them off into an oxbow, and reconnect the
    /// channel on the short path. Repeats until no pinch remains.
    private func cutOffLoops() {
        // Points this close *along the river* never count as a pinch, so a
        // tight bend's own flanks cannot cut themselves off.
        let skip = Swift.max(Int(((cutoffDistance + 20 * spacing) / spacing).rounded()), 2)
        while let (from, to) = firstPinch(skippingWithin: skip) {
            let loop = Array(centerline[from ... to])
            oxbows.append(Oxbow(points: loop, age: 0))
            centerline = Array(centerline[0 ... from]) + Array(centerline[to...])
        }
    }

    /// The first pair of centerline indices closer than `cutoffDistance`
    /// across the land while at least `skip` indices apart along it.
    private func firstPinch(skippingWithin skip: Int) -> (Int, Int)? {
        let n = centerline.count
        let threshold = cutoffDistance * cutoffDistance
        guard n > skip else { return nil }
        for i in 0 ..< (n - skip) {
            let p = centerline[i]
            for j in (i + skip) ..< n {
                let dx = centerline[j].x - p.x
                let dy = centerline[j].y - p.y
                if dx * dx + dy * dy < threshold { return (i, j) }
            }
        }
        return nil
    }

    /// Age every oxbow, shrink it toward its center, and delete the ones
    /// smaller than the channel width.
    private func ageOxbows() {
        guard !oxbows.isEmpty else { return }
        var kept: [Oxbow] = []
        kept.reserveCapacity(oxbows.count)
        for var oxbow in oxbows {
            oxbow.age += 1
            var center = Vector2.zero
            for p in oxbow.points { center = center + p }
            center = center * (1 / Double(Swift.max(oxbow.points.count, 1)))
            let keepFactor = 1 - Swift.min(Swift.max(oxbowShrink, 0), 1)
            var radius = 0.0
            for i in oxbow.points.indices {
                oxbow.points[i] = center + (oxbow.points[i] - center) * keepFactor
                radius = Swift.max(radius, oxbow.points[i].distance(to: center))
            }
            if radius > width / 2 { kept.append(oxbow) }
        }
        oxbows = kept
    }

    // MARK: - Spline resample (file-private)

    /// Redraw `points` at an even `spacing` through an interpolating spline
    /// (a piecewise cubic through the points themselves). A straight-segment
    /// resample would shave a little curvature off every step, and curvature
    /// is the engine here, so the cubic is load-bearing.
    static func resampledThroughSpline(_ points: [Vector2], spacing: Double) -> [Vector2] {
        let n = points.count
        guard n >= 4, spacing > 0 else { return points }

        var total = 0.0
        var cumulative = [Double](repeating: 0, count: n)
        for i in 1 ..< n {
            total += points[i].distance(to: points[i - 1])
            cumulative[i] = total
        }
        guard total > spacing * 2 else { return points }

        let sampleCount = Swift.max(Int((total / spacing).rounded()) + 1, 4)
        var result = [Vector2]()
        result.reserveCapacity(sampleCount)
        var segmentIndex = 1
        for k in 0 ..< sampleCount {
            let target = total * Double(k) / Double(sampleCount - 1)
            while segmentIndex < n - 1, cumulative[segmentIndex] < target {
                segmentIndex += 1
            }
            let a = segmentIndex - 1
            let span = cumulative[segmentIndex] - cumulative[a]
            let t = span > 1e-12 ? (target - cumulative[a]) / span : 0
            let p0 = points[Swift.max(a - 1, 0)]
            let p1 = points[a]
            let p2 = points[segmentIndex]
            let p3 = points[Swift.min(segmentIndex + 1, n - 1)]
            result.append(catmullRom(p0, p1, p2, p3, t))
        }
        return result
    }

    /// One cubic segment through `p1` and `p2`, with `p0`/`p3` shaping the
    /// tangents, evaluated at `t` in 0...1.
    private static func catmullRom(_ p0: Vector2, _ p1: Vector2,
                                   _ p2: Vector2, _ p3: Vector2,
                                   _ t: Double) -> Vector2 {
        let t2 = t * t
        let t3 = t2 * t
        let x = 0.5 * (2 * p1.x
            + (p2.x - p0.x) * t
            + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2
            + (3 * p1.x - p0.x - 3 * p2.x + p3.x) * t3)
        let y = 0.5 * (2 * p1.y
            + (p2.y - p0.y) * t
            + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2
            + (3 * p1.y - p0.y - 3 * p2.y + p3.y) * t3)
        return Vector2(x, y)
    }
}

// MARK: - Seed factories

public extension Meander {
    /// A stepper seeded with a gently wavy line from `start` to `end`: a few
    /// long sine components at random phases, in the wavelength band the
    /// migration amplifies (several channel widths), tapered to nothing at
    /// the pinned ends. The migration takes it from there.
    static func line(from start: Vector2,
                     to end: Vector2,
                     seed: UInt64 = 0,
                     width: Double = 24,
                     migrationRate: Double? = nil,
                     memoryLength: Double? = nil,
                     spacing: Double? = nil,
                     cutoffDistance: Double? = nil,
                     recordEvery: Int = 0) -> Meander {
        var rng = SplitMix64(seed: seed)
        let along = end - start
        let length = along.length
        let waves = (0 ..< 3).map { _ -> (wavelength: Double, phase: Double, amplitude: Double) in
            (wavelength: Double.random(in: 6 ... 16, using: &rng) * width,
             phase: Double.random(in: 0 ..< 2 * .pi, using: &rng),
             amplitude: width * Double.random(in: 0.2 ... 0.5, using: &rng))
        }
        let step = spacing ?? width / 4
        let count = Swift.max(Int((length / step).rounded()), 8)
        let points = (0 ... count).map { i -> Vector2 in
            let t = Double(i) / Double(count)
            let base = Vector2(start.x + along.x * t, start.y + along.y * t)
            guard length > 1e-9 else { return base }
            var offset = 0.0
            for wave in waves {
                offset += sin(t * length / wave.wavelength * 2 * .pi + wave.phase) * wave.amplitude
            }
            offset *= sin(t * .pi)          // taper to zero at the pinned ends
            return Vector2(base.x + offset * (along.y / length),
                           base.y - offset * (along.x / length))
        }
        return Meander(centerline: points, seed: seed &+ 1, width: width,
                       migrationRate: migrationRate, memoryLength: memoryLength,
                       spacing: spacing, cutoffDistance: cutoffDistance,
                       recordEvery: recordEvery)
    }
}
