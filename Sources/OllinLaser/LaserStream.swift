import Foundation
import Ollin

/// One position the galvos are asked to hold for one tick of the point clock,
/// with the beam either lit in a color or blanked.
///
/// A laser has no notion of a line: it has a mirror pair that visits positions
/// at a fixed rate, and a beam that is on or off at each one. A `LaserStream`
/// is that visit list, and this is one entry in it. Positions are in projector
/// space (`-1…1`, x right, y up; see `ProjectorSpace`).
public struct LaserPoint: Equatable, Sendable {

    /// Where the galvos point, in projector space.
    public var position: Vector2

    /// The color the beam is driven to. Black when blanked.
    public var color: Color

    /// Whether the beam is off for this point. Blanked points are what carry
    /// the beam between separate paths without drawing a line between them.
    public var isBlanked: Bool

    /// A lit point.
    public init(_ position: Vector2, color: Color) {
        self.position = position
        self.color = color
        self.isBlanked = false
    }

    /// A blanked point: a position the galvos travel through with the beam off.
    public init(blankedAt position: Vector2) {
        self.position = position
        self.color = .black
        self.isBlanked = true
    }

    init(position: Vector2, color: Color, isBlanked: Bool) {
        self.position = position
        self.color = isBlanked ? .black : color
        self.isBlanked = isBlanked
    }
}

/// A frame's worth of line work turned into the point list a projector plays,
/// with the measurements that say whether it will look the way it should.
///
/// The stream is what `LaserOptimizer` produces and what a `LaserProjector`
/// sends. It also carries enough to draw itself: `canvas` is the region the
/// frame was measured in, so `drawLaserPreview` can put the beam's own path
/// back on screen.
public struct LaserStream: Sendable {

    /// Every point, in play order. Playing the list end to end and starting
    /// again repeats the frame: the walk back from the last path to the first
    /// is part of the list, so a loop has no seam.
    public var points: [LaserPoint]

    /// The canvas region the frame was measured in.
    public var canvas: Rectangle

    /// The point clock the projector runs at, in points per second.
    public var pointsPerSecond: Int

    /// Points the frame may hold at the wanted refresh rate: the point rate
    /// divided by that rate.
    public var pointBudget: Int

    /// Field units walked with the beam lit (the line work itself).
    public var drawnLength: Double

    /// Field units walked with the beam blanked (the dark travel between
    /// paths). Path ordering exists to make this number small.
    public var travelLength: Double

    /// How many paths the frame held after empty ones were dropped.
    public var pathCount: Int

    public init(points: [LaserPoint], canvas: Rectangle, pointsPerSecond: Int,
                pointBudget: Int, drawnLength: Double, travelLength: Double,
                pathCount: Int) {
        self.points = points
        self.canvas = canvas
        self.pointsPerSecond = pointsPerSecond
        self.pointBudget = pointBudget
        self.drawnLength = drawnLength
        self.travelLength = travelLength
        self.pathCount = pathCount
    }

    /// Points with the beam lit.
    public var litCount: Int { points.count(where: { !$0.isBlanked }) }

    /// Points with the beam blanked.
    public var blankedCount: Int { points.count(where: { $0.isBlanked }) }

    /// How long one pass of the frame takes, in seconds.
    public var duration: Double {
        pointsPerSecond > 0 ? Double(points.count) / Double(pointsPerSecond) : 0
    }

    /// How often the frame repeats, in frames per second. Below about 20 the
    /// eye starts to see it flicker rather than stand still.
    public var refreshRate: Double {
        duration > 0 ? 1 / duration : 0
    }

    /// Whether the frame holds more points than the wanted refresh rate allows.
    /// Nothing is dropped when it does: the frame plays whole and repeats more
    /// slowly, so the picture flickers. Draw less line work, or raise
    /// `LaserOptimizer.spacing`, to bring it back under.
    public var isOverBudget: Bool { points.count > pointBudget }

    /// A stream with no points at all: nothing to play.
    public static func empty(canvas: Rectangle, pointsPerSecond: Int, pointBudget: Int) -> LaserStream {
        LaserStream(points: [], canvas: canvas, pointsPerSecond: pointsPerSecond,
                    pointBudget: pointBudget, drawnLength: 0, travelLength: 0, pathCount: 0)
    }

    /// One line of plain facts about the frame, for a caption or a log.
    public var summary: String {
        let rate = String(format: "%.0f", refreshRate)
        let over = isOverBudget ? " (over budget)" : ""
        return "\(points.count) points, \(litCount) lit, \(rate) fps\(over)"
    }
}
