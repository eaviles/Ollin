import Foundation
import Ollin

/// Turns a frame of line work into the point stream a projector plays, and
/// this is where the craft of laser projection lives.
///
/// A projector visits positions at a fixed rate. Everything about how the
/// picture looks follows from where those positions are put:
///
/// - **Spacing.** Points are spread evenly along each line, so the beam moves
///   at a steady speed and the line is evenly bright. A long segment drawn
///   with two points is scanned fast and reads faint.
/// - **Corners.** The mirrors have mass. Asked to turn a sharp corner at
///   speed, they overshoot and round it off, so a few points are held at the
///   corner to let them arrive before the next line starts.
/// - **Blanking.** Between two separate paths the beam goes off and the
///   mirrors travel. Points are held at each end of that jump as well, or the
///   beam lights while the mirrors are still moving and drags a faint tail
///   between the shapes.
/// - **Order.** The dark travel is wasted time, and time is the whole budget,
///   so paths are visited in a near order rather than the order they arrived.
/// - **Budget.** The point rate divided by the wanted refresh rate is all the
///   points a frame may hold. Past that the frame still plays whole, and
///   repeats more slowly, which the eye sees as flicker.
///
/// The defaults are deliberately careful: a slower point rate than most
/// projectors are rated for, and generous dwells. Raise them once you can see
/// what your own machine does with them.
///
/// ```swift
/// var optimizer = LaserOptimizer()
/// optimizer.pointsPerSecond = 30_000     // what the projector is rated for
/// optimizer.spacing = 0.015              // finer line work, more points
/// let stream = optimizer.stream(frame)
/// ```
public struct LaserOptimizer: Sendable {

    /// The projector's point clock, in points per second. 30,000 is the rate
    /// most consumer projectors are sold against, measured on the ILDA test
    /// pattern; the default sits below it because a projector asked for more
    /// than it can scan distorts rather than complains.
    public var pointsPerSecond: Int = 20_000

    /// How often the frame should repeat, in frames per second. With the point
    /// rate, this sets the budget: a frame that needs more points than
    /// `pointsPerSecond / refreshRate` repeats more slowly and flickers.
    public var refreshRate: Double = 30

    /// The distance between lit points, in field units (the field is 2 wide).
    /// Smaller means smoother, brighter line work and more points spent.
    public var spacing: Double = 0.02

    /// The distance between blanked points on a jump between paths. Wider than
    /// `spacing`, because nobody sees the travel and the time is better spent
    /// on the line work; too wide asks the mirrors for a jump they cannot make.
    public var travelSpacing: Double = 0.08

    /// How sharp a turn has to be, in radians, before points are held at it.
    /// The default is 30 degrees.
    public var cornerAngle: Double = .pi / 6

    /// How many extra points to hold at a sharp corner.
    public var cornerDwell: Int = 3

    /// How many points to hold at each end of a blanked jump, so the mirrors
    /// settle before the beam lights and after it goes out.
    public var blankingDwell: Int = 4

    /// Whether to reorder the paths to shorten the dark travel between them.
    /// The walk is greedy and near, not perfect, and it may enter a closed
    /// path at any of its points or walk an open one backwards. It changes the
    /// order the picture is drawn in, never the picture.
    public var reordersPaths: Bool = true

    public init() {}

    /// How many points a frame may hold at the current rate and refresh.
    public var pointBudget: Int {
        refreshRate > 0 ? Int((Double(pointsPerSecond) / refreshRate).rounded(.down)) : Int.max
    }

    // MARK: The pipeline

    /// Turn a frame of line work into the point stream to play.
    public func stream(_ frame: LaserFrame) -> LaserStream {
        let paths = prepared(frame)
        guard !paths.isEmpty else {
            return .empty(canvas: frame.canvas, pointsPerSecond: pointsPerSecond,
                          pointBudget: pointBudget)
        }

        var points: [LaserPoint] = []
        var drawn = 0.0
        var travel = 0.0
        let dwell = max(0, blankingDwell)

        for (i, path) in paths.enumerated() {
            let start = path.points[0]
            // Settle at the entry with the beam off, then draw.
            for _ in 0..<dwell { points.append(LaserPoint(blankedAt: start)) }
            drawn += emit(path, into: &points)

            // Settle at the exit, still dark, then travel to the next entry.
            let end = points.last?.position ?? start
            for _ in 0..<dwell { points.append(LaserPoint(blankedAt: end)) }
            // The frame repeats, so the last path travels back to the first:
            // the loop then has no seam to hide.
            let next = paths[(i + 1) % paths.count].points[0]
            travel += travelling(from: end, to: next, into: &points)
        }

        return LaserStream(points: points, canvas: frame.canvas,
                           pointsPerSecond: pointsPerSecond, pointBudget: pointBudget,
                           drawnLength: drawn, travelLength: travel,
                           pathCount: paths.count)
    }

    // MARK: Preparation

    /// The frame's paths in projector space: mapped, clamped into the field,
    /// stripped of repeated points and empty paths, and put in walking order.
    private func prepared(_ frame: LaserFrame) -> [FieldPath] {
        let toField = ProjectorSpace.transform(from: frame.canvas)
        var paths: [FieldPath] = []
        for path in frame.paths {
            guard path.points.count >= 2 else { continue }
            let multicolored = path.isMulticolored
            var points: [Vector2] = []
            var colors: [Color] = []
            points.reserveCapacity(path.points.count)
            for (i, point) in path.points.enumerated() {
                let mapped = ProjectorSpace.clamped(toField(point))
                // A repeated point is a point spent on nothing; the dwell rules
                // below decide where points are held, not the incoming data.
                if let last = points.last, (mapped - last).length < 1e-9 { continue }
                points.append(mapped)
                colors.append(multicolored ? path.colors[i] : path.color(at: 0))
            }
            // A closed path that repeats its first point at the end would draw
            // its closing segment twice, so the repeat goes as well.
            if path.isClosed, points.count > 2, (points[points.count - 1] - points[0]).length < 1e-9 {
                points.removeLast()
                colors.removeLast()
            }
            guard points.count >= 2 else { continue }
            paths.append(FieldPath(points: points, colors: colors, isClosed: path.isClosed))
        }
        // The tour runs for one path as well as for many: entering an open path
        // at the end nearer the beam is the same decision either way.
        guard reordersPaths, !paths.isEmpty else { return paths }

        let contours = paths.map { Contour($0.points, closed: $0.isClosed) }
        return orderedPathSteps(contours, from: .zero).map { step in
            paths[step.index].entered(at: step.entry)
        }
    }

    // MARK: Emission

    /// Lay one path down as lit points, holding a few at each sharp corner.
    /// Returns the field distance drawn.
    private func emit(_ path: FieldPath, into points: inout [LaserPoint]) -> Double {
        let step = max(spacing, 1e-6)
        var walk = path.points
        var colors = path.colors
        if path.isClosed {
            walk.append(path.points[0])
            colors.append(path.colors[0])
        }

        var drawn = 0.0
        points.append(LaserPoint(walk[0], color: colors[0]))
        for i in 1..<walk.count {
            let a = walk[i - 1], b = walk[i]
            let length = (b - a).length
            drawn += length
            // Subdivide rather than resample: every point the sketch gave is
            // kept exactly where it put it, so a corner stays a corner.
            let steps = max(1, Int((length / step).rounded(.up)))
            for k in 1...steps {
                let t = Double(k) / Double(steps)
                points.append(LaserPoint(a + (b - a) * t,
                                         color: blend(colors[i - 1], colors[i], t)))
            }
            // Hold at the vertex just laid down when the path turns sharply
            // there. The last vertex of a closed path is the seam, which is a
            // corner like any other.
            let after = i + 1 < walk.count ? walk[i + 1] : (path.isClosed ? walk[1] : nil)
            if let after, isCorner(a, b, after) {
                for _ in 0..<max(0, cornerDwell) {
                    points.append(LaserPoint(b, color: colors[i]))
                }
            }
        }
        return drawn
    }

    /// Walk the beam from one path's exit to the next path's entry with it off.
    /// The ends are already held by the blanking dwell, so only the points
    /// strictly between them are laid down. Returns the field distance moved.
    private func travelling(from a: Vector2, to b: Vector2,
                            into points: inout [LaserPoint]) -> Double {
        let length = (b - a).length
        guard length > 1e-9 else { return 0 }
        let steps = max(1, Int((length / max(travelSpacing, 1e-6)).rounded(.up)))
        if steps > 1 {
            for k in 1..<steps {
                points.append(LaserPoint(blankedAt: a + (b - a) * (Double(k) / Double(steps))))
            }
        }
        return length
    }

    /// Whether the turn at `b`, arriving from `a` and leaving for `c`, is sharp
    /// enough to hold points at.
    private func isCorner(_ a: Vector2, _ b: Vector2, _ c: Vector2) -> Bool {
        guard cornerDwell > 0 else { return false }
        let into = b - a, outOf = c - b
        let lengths = into.length * outOf.length
        guard lengths > 1e-12 else { return false }
        let cosine = min(max((into.x * outOf.x + into.y * outOf.y) / lengths, -1), 1)
        return acos(cosine) > cornerAngle
    }

    /// Cross-fade two colors along a segment. Per channel, not through a
    /// perceptual space: each of the three diodes is driven separately, and
    /// the fade is what its own drive level does between the two ends.
    private func blend(_ a: Color, _ b: Color, _ t: Double) -> Color {
        if a == b { return a }
        func lerp(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        return Color(red: lerp(a.red, b.red), green: lerp(a.green, b.green),
                     blue: lerp(a.blue, b.blue), alpha: lerp(a.alpha, b.alpha))
    }
}

// MARK: - Paths in projector space

/// A frame path mapped into the projector's field, carrying a color per point
/// so reversing or rotating it keeps the colors with the points they belong to.
struct FieldPath {
    var points: [Vector2]
    var colors: [Color]
    var isClosed: Bool

    /// The same path walked from vertex `entry`: a closed path rotates to start
    /// there, an open one entered at its last vertex is walked backwards.
    func entered(at entry: Int) -> FieldPath {
        if isClosed {
            guard entry > 0, entry < points.count else { return self }
            return FieldPath(points: Array(points[entry...]) + Array(points[..<entry]),
                             colors: Array(colors[entry...]) + Array(colors[..<entry]),
                             isClosed: true)
        }
        guard entry != 0 else { return self }
        return FieldPath(points: points.reversed(), colors: colors.reversed(), isClosed: false)
    }
}
