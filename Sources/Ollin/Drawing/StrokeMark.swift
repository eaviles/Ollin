import Foundation

/// A mark as it was made: a path plus, at every point of it, the width and
/// opacity the hand asked for there. Draw it with `drawMark(_:)`.
///
/// A mark is the recorded half of stroke dynamics. Feed it the pointer once per
/// frame and it measures how fast the pointer is traveling and how hard it is
/// pressed, smooths both, runs them through its `StrokeDynamics`, and keeps the
/// answer alongside the position:
///
/// ```swift
/// var mark = StrokeMark(.speed(fast: 0.15, fastOpacity: 0.4))
///
/// override func draw() {
///     background(.white)
///     if mouseIsPressed { record(into: &mark) }
///     stroke(.black)
///     strokeWeight(24)
///     drawMark(mark)
/// }
/// ```
///
/// It is an ordinary value, so keeping a finished mark is a copy and starting
/// the next one is `clear()`:
///
/// ```swift
/// override func mouseReleased() {
///     finished.append(mark)
///     mark.clear()
/// }
/// ```
///
/// A mark can also be built outright from samples you already have, which is how
/// one gets drawn without a pointer at all: replaying a gesture, exporting
/// deterministically, or turning some other measured signal into a stroke.
///
/// Width is why a mark exists rather than a `StrokeProfile`. A profile is read
/// as a function of the fraction along a finished path, and a recorded mark's
/// points are not evenly spaced along its length. They are dense where the hand
/// slowed and sparse where it hurried, which is exactly the information the mark
/// is carrying. So a mark keeps its widths *at* its points and hands the
/// renderer their real positions along the path.
public struct StrokeMark: Sendable {

    /// One recorded point: where the mark was, and what it asked for there.
    public struct Sample: Sendable, Equatable {
        /// The position in canvas coordinates.
        public var position: Vector2
        /// The width multiplier on `strokeWeight` at this point.
        public var width: Double
        /// The opacity multiplier on the stroke color's alpha at this point.
        public var opacity: Double

        public init(position: Vector2, width: Double = 1, opacity: Double = 1) {
            self.position = position
            self.width = width
            self.opacity = opacity
        }
    }

    /// The recorded points, in the order they were made.
    public private(set) var samples: [Sample] = []

    /// How measured motion becomes width and opacity. Settable mid-mark, so a
    /// live knob can change the brush while a stroke is in progress; points
    /// already recorded keep what they were given.
    public var dynamics: StrokeDynamics

    /// How far the pointer must travel before a new point is recorded, in canvas
    /// points. It keeps a slow hand from piling hundreds of near-identical
    /// points into one spot, and it is what makes the recorded speed meaningful:
    /// each step spans a real distance over a real time. Set it to `0` to record
    /// every frame.
    public var minimumSpacing: Double

    /// How much the measured speed and pressure are smoothed, `0` (raw, jumpy)
    /// to `1` (heavy, laggy). Raw per-frame speed is far too noisy to drive a
    /// width directly; the default sits where a mark reads as deliberate without
    /// visibly trailing the pointer.
    public var smoothing: Double

    /// Speed and pressure each get their own adaptive low-pass. The filter is
    /// the right tool here rather than a fixed average because a stroke is both
    /// things at once: nearly still while a hand sets up (where jitter shows and
    /// smoothing should be heavy) and fast through the middle (where lag shows
    /// and smoothing should get out of the way).
    private var speedFilter = OneEuroFilter<Double>(minCutoff: 3, beta: 0.03)
    private var pressureFilter = OneEuroFilter<Double>(minCutoff: 3, beta: 0.03)

    /// Time banked since the last recorded point, including frames whose motion
    /// fell under `minimumSpacing`. Spending it all on the point that finally
    /// qualifies is what makes the measured speed independent of the frame rate.
    private var pendingTime: Double = 0

    /// Distance traveled so far, handed to the dynamics as `StrokeInput.distance`.
    private var traveled: Double = 0

    /// The first point, held back until a second one gives it a direction. A
    /// mark of one point draws nothing anyway, so nothing is lost by waiting,
    /// and a direction-driven brush gets an honest heading at the very start
    /// instead of a made-up one.
    private var pending: (position: Vector2, pressure: Double)?

    /// A speed in points per second runs in the hundreds, while the filter's
    /// `beta` is in the units of whatever it is filtering. Scaling speed to
    /// roughly `0...1` before filtering keeps `beta` in the range its tuning
    /// advice assumes.
    private static let speedScale = 1000.0

    /// An empty mark, ready to record.
    public init(_ dynamics: StrokeDynamics = .speed(),
                smoothing: Double = 0.5,
                minimumSpacing: Double = 1.5) {
        self.dynamics = dynamics
        self.smoothing = smoothing
        self.minimumSpacing = minimumSpacing
    }

    /// A mark built from samples you already have, for replaying a gesture or
    /// drawing one deterministically. Recording continues from the last sample.
    public init(samples: [Sample],
                dynamics: StrokeDynamics = .speed(),
                smoothing: Double = 0.5,
                minimumSpacing: Double = 1.5) {
        self.init(dynamics, smoothing: smoothing, minimumSpacing: minimumSpacing)
        self.samples = samples
        for (a, b) in zip(samples, samples.dropFirst()) {
            traveled += (b.position - a.position).length
        }
    }

    // MARK: Recording

    /// Record where the pointer is now. `dt` is the time since the last call
    /// (pass `deltaTime`), which is what keeps the measured speed the same
    /// whether the sketch is running at 60 or 120 frames per second. `pressure`
    /// is `0...1`; leave it out on an input that has none.
    ///
    /// A call closer than `minimumSpacing` to the last recorded point banks its
    /// time and returns without recording, so the next point that does qualify
    /// measures its speed over the whole interval.
    ///
    /// The `Sketch.record(into:)` sugar fills all three arguments from the
    /// running sketch.
    public mutating func record(_ position: Vector2, dt: Double, pressure: Double = 1) {
        pendingTime += max(dt, 0)
        let force = min(max(pressure, 0), 1)

        guard let last = samples.last ?? pending.map({ Sample(position: $0.position) }) else {
            // Nothing recorded yet: hold this point until a second one arrives to
            // give it a heading, and seed the filters from it.
            pending = (position, force)
            _ = speedFilter.filter(0, dt: max(pendingTime, 1e-6))
            _ = pressureFilter.filter(force, dt: max(pendingTime, 1e-6))
            pendingTime = 0
            return
        }

        let step = position - last.position
        let distance = step.length
        guard distance >= minimumSpacing else { return }

        let elapsed = max(pendingTime, 1e-6)
        pendingTime = 0
        let direction = step / distance

        // Speed over the interval this point actually spans, then smoothed.
        let cutoff = Self.cutoff(for: smoothing)
        speedFilter.minCutoff = cutoff
        pressureFilter.minCutoff = cutoff
        let raw = distance / elapsed
        let speed = max(0, speedFilter.filter(raw / Self.speedScale, dt: elapsed) * Self.speedScale)
        let smoothedForce = min(max(pressureFilter.filter(force, dt: elapsed), 0), 1)

        // The held first point can be placed now that the heading is known.
        if let first = pending {
            store(first.position,
                  StrokeInput(speed: 0, pressure: first.pressure,
                              direction: direction, distance: 0))
            pending = nil
        }

        traveled += distance
        store(position,
              StrokeInput(speed: speed, pressure: smoothedForce,
                          direction: direction, distance: traveled))
    }

    /// Throw away everything recorded and reset the measurement, ready for the
    /// next mark. Keeps `dynamics`, `smoothing`, and `minimumSpacing`.
    public mutating func clear() {
        samples.removeAll(keepingCapacity: true)
        speedFilter = OneEuroFilter<Double>(minCutoff: 3, beta: 0.03)
        pressureFilter = OneEuroFilter<Double>(minCutoff: 3, beta: 0.03)
        pendingTime = 0
        traveled = 0
        pending = nil
    }

    /// Add a finished sample, width and opacity already decided. The dynamics do
    /// not see it, which is the point: this is how a mark is built from
    /// something that is not a pointer, or replayed exactly.
    public mutating func append(_ sample: Sample) {
        if let last = samples.last { traveled += (sample.position - last.position).length }
        samples.append(sample)
    }

    private mutating func store(_ position: Vector2, _ input: StrokeInput) {
        let m = dynamics.multipliers(for: input)
        samples.append(Sample(position: position, width: m.width, opacity: m.opacity))
    }

    /// The smoothing knob as a filter cutoff in hertz. Cutoffs are heard
    /// logarithmically, so the knob spans the range that way too: about 15 Hz
    /// (effectively raw) at `0`, 3 Hz at the default, and under 1 Hz at `1`.
    private static func cutoff(for smoothing: Double) -> Double {
        15 * pow(0.05, min(max(smoothing, 0), 1))
    }

    // MARK: Reading

    /// Whether the mark has anything to draw. A single recorded point is not a
    /// mark yet: it has no direction and no length.
    public var isEmpty: Bool { samples.count < 2 }

    /// How many points are recorded.
    public var count: Int { samples.count }

    /// The recorded path on its own, for handing to anything that takes points
    /// (`drawPolyline`, `Contour`, the geometry helpers).
    public var positions: [Vector2] { samples.map(\.position) }

    /// How far the mark has traveled, in canvas points.
    public var length: Double { traveled }

    /// The box the recorded points fall in, or `nil` when nothing is recorded.
    /// It ignores stroke width, like every other `bounds` in the geometry
    /// vocabulary.
    public var bounds: Rectangle? {
        guard let first = samples.first else { return nil }
        var lo = first.position, hi = first.position
        for s in samples.dropFirst() {
            lo = Vector2(min(lo.x, s.position.x), min(lo.y, s.position.y))
            hi = Vector2(max(hi.x, s.position.x), max(hi.y, s.position.y))
        }
        return Rectangle(x: lo.x, y: lo.y, width: hi.x - lo.x, height: hi.y - lo.y)
    }

    /// The fraction along the mark's length at each sample, `0` at the first and
    /// `1` at the last. This is what lets the recorded widths reach the stroke
    /// expander at their true positions rather than spread evenly.
    var pathFractions: [Double] {
        let n = samples.count
        guard n > 1 else { return n == 1 ? [0] : [] }
        var cumulative = [Double](repeating: 0, count: n)
        for i in 1..<n {
            cumulative[i] = cumulative[i - 1] + (samples[i].position - samples[i - 1].position).length
        }
        let total = cumulative[n - 1]
        guard total > 0 else { return (0..<n).map { Double($0) / Double(n - 1) } }
        return cumulative.map { $0 / total }
    }

    /// The mark's opacity averaged along its length, which is the single value a
    /// vector document can carry for the whole path. Weighted by distance rather
    /// than by point count, so a moment the hand lingered over does not outvote
    /// the long sweep it came from.
    var averageOpacity: Double {
        guard samples.count > 1 else { return samples.first?.opacity ?? 1 }
        var weighted = 0.0, total = 0.0
        for (a, b) in zip(samples, samples.dropFirst()) {
            let span = (b.position - a.position).length
            weighted += (a.opacity + b.opacity) / 2 * span
            total += span
        }
        return total > 0 ? weighted / total : samples[0].opacity
    }

    /// Whether any recorded point asks for something other than the stroke's own
    /// weight. When nothing does, the mark takes the plain constant-width path
    /// and draws byte for byte like an ordinary polyline.
    var variesWidth: Bool {
        samples.contains { abs($0.width - 1) > 1e-9 }
    }

    /// Whether any recorded point asks for something other than the stroke
    /// color's own alpha, which is what decides if the per-point alpha channel
    /// is touched at all.
    var variesOpacity: Bool {
        samples.contains { abs($0.opacity - 1) > 1e-9 }
    }
}
