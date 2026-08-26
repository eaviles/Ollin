import Foundation
import Ollin

/// The rules that stand between a sketch and the beam.
///
/// A projector is not a screen. The light it puts out is collimated, and the
/// mirrors are the only thing spreading it: while they sweep, the power lands
/// across a whole line, and while they sit still it lands on one spot. So the
/// two ways a laser sketch goes wrong are a beam that stops moving and a beam
/// that is brighter than the room can take, and both of them are the
/// framework's business rather than the sketch's.
///
/// Every stream a `LaserProjector` sends passes through these rules, and the
/// projector will not send anything at all until it is armed. The defaults are
/// careful. Loosen them only against your own machine, in your own room.
///
/// ```swift
/// var safety = LaserSafety()
/// safety.maximumBrightness = 0.3      // quieter still
/// safety.stallTimeout = 0.25          // blank sooner if the sketch stops
/// ```
public struct LaserSafety: Sendable {

    /// A ceiling on every color channel, `0…1`. The default halves the drive,
    /// because a projector at full power is the wrong way to find out that the
    /// geometry is wrong.
    public var maximumBrightness: Double = 0.5

    /// How far the beam has to move, in field units, to count as moving.
    public var stationaryRadius: Double = 0.004

    /// How many lit points in a row may stay inside `stationaryRadius` before
    /// the beam is blanked. This has to sit above `LaserOptimizer.cornerDwell`,
    /// which holds a few points at a corner on purpose; the default leaves
    /// plenty of room over it.
    public var stationaryLimit: Int = 24

    /// How long the projector will play the last frame it was given, in
    /// seconds, before it blanks. A sketch that stops calling `send` (it
    /// stalled, it crashed, a window closed) leaves a live stream behind, and
    /// a live stream that never changes is a stopped beam.
    public var stallTimeout: Double = 0.5

    public init() {}

    /// Every rule turned off. For a bench where the beam goes into a meter
    /// rather than a room, and for tests that want to see the raw stream.
    /// Nothing in the framework selects this for you.
    public static var unguarded: LaserSafety {
        var safety = LaserSafety()
        safety.maximumBrightness = 1
        safety.stationaryLimit = .max
        safety.stallTimeout = .infinity
        return safety
    }

    // MARK: Applying the rules

    /// The stream as it may actually be played: dimmed to the ceiling, and
    /// blanked wherever the beam would sit still.
    public func guarded(_ stream: LaserStream) -> LaserStream {
        var out = stream
        out.points = guarded(stream.points)
        return out
    }

    /// The point list as it may actually be played.
    public func guarded(_ points: [LaserPoint]) -> [LaserPoint] {
        let ceiling = min(max(maximumBrightness, 0), 1)
        var out: [LaserPoint] = []
        out.reserveCapacity(points.count)

        var anchor: Vector2?          // where the current lit run began
        var held = 0                  // lit points spent inside the radius

        for point in points {
            guard !point.isBlanked else {
                anchor = nil
                held = 0
                out.append(point)
                continue
            }
            if let start = anchor, (point.position - start).length <= stationaryRadius {
                held += 1
            } else {
                anchor = point.position
                held = 1
            }
            if held > stationaryLimit {
                out.append(LaserPoint(blankedAt: point.position))
            } else {
                out.append(LaserPoint(point.position, color: dimmed(point.color, ceiling)))
            }
        }
        return out
    }

    /// A blanked hold at the field center: what a projector plays when it has
    /// nothing to draw, when it is not armed, and when the sketch has stopped
    /// feeding it. The mirrors have somewhere to be, and the beam is off.
    public static func blankHold(count: Int = 64) -> [LaserPoint] {
        Array(repeating: LaserPoint(blankedAt: .zero), count: max(1, count))
    }

    private func dimmed(_ color: Color, _ ceiling: Double) -> Color {
        guard ceiling < 1 else { return color }
        return Color(red: color.red * ceiling, green: color.green * ceiling,
                     blue: color.blue * ceiling, alpha: color.alpha)
    }
}
