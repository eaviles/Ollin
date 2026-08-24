import Foundation

/// A spirolateral: step 1, 2, 3 … `order` lengths, turn the same way by the same
/// angle after every step, then run the whole sequence again, and again, until
/// the walk arrives back where it started facing the way it set off.
///
/// The rule is a schoolroom doodle, and the figure it makes is not obvious from
/// it. Frank Odds named and studied them in 1973, and the walk turned up again as
/// a turtle-geometry exercise: the same few numbers draw a square knot, a
/// pinwheel, or a shape that never closes at all.
///
/// ```swift
/// let figure = spirolateral(order: 7, step: 26)
/// noFill(); stroke(.white); strokeWeight(2)
/// drawPolyline(fitted(figure.points, in: bounds.inset(by: 60)), closed: figure.closes)
/// ```
///
/// Whether it closes is settled before a single point is placed. One run turns
/// the walker through `netTurn`, so run `m` is run 1 turned by `m` of those. The
/// runs therefore close into a ring as soon as a whole number of them makes a
/// whole number of turns, and the figure that comes out has that many arms about
/// `center`. When `netTurn` is itself a whole number of turns, no amount of
/// repeating helps: every run leaves the walker further from home in the same
/// direction, and the figure walks off the page.
public struct Spirolateral: Equatable, Sendable {
    /// How many steps one run takes. The steps are 1, 2, 3 … `order` lengths long.
    public let order: Int
    /// The angle turned after every step, in radians. A positive turn reads
    /// clockwise on the canvas, where y grows downward.
    public let turn: Double
    /// The length of the first step. Step `i` is `i` of these.
    public let step: Double
    /// The step numbers (1 through `order`) whose turn goes the other way. This is
    /// the reversed spirolateral, and it draws a different figure from the same
    /// order.
    public let reversed: Set<Int>
    /// How many runs were walked.
    public let repeats: Int
    /// The number of runs that brings the walk home, or nil when no number of them
    /// ever does.
    public let closingRepeats: Int?
    /// Whether the walk as drawn comes home, which asks both that a closing count
    /// exists and that `repeats` is a whole number of them.
    public let closes: Bool
    /// Every corner of the walk, in the order it was walked, starting at the
    /// origin. A walk that comes home does not repeat its first point at the end.
    public let points: [Vector2]
    /// The angle one run turns the walker through. The figure closes once a whole
    /// number of these makes a whole number of turns.
    public let netTurn: Double
    /// Where one run leaves the walker, measured from where that run started.
    public let runDisplacement: Vector2
    /// The point the figure turns about, or nil when every run leaves the walker
    /// facing the same way and the walk therefore drifts.
    public let center: Vector2?

    /// Walk a spirolateral. Leave `repeats` nil to walk as many runs as it takes
    /// to come home, looking up to `maxRepeats` of them.
    ///
    /// - Parameters:
    ///   - order: how many steps one run takes.
    ///   - turn: the angle turned after every step. A quarter turn is the classic.
    ///   - step: the length of the first step.
    ///   - reversed: the step numbers whose turn goes the other way.
    ///   - repeats: how many runs to walk, or nil for as many as it takes.
    ///   - maxRepeats: how far to look for a closing count before giving up.
    public init(order: Int, turn: Double = .pi / 2, step: Double = 1,
                reversed: Set<Int> = [], repeats: Int? = nil, maxRepeats: Int = 360) {
        let order = Swift.max(0, order)
        self.order = order
        self.turn = turn
        self.step = step
        self.reversed = reversed

        guard order > 0, step != 0 else {
            self.repeats = 0
            closingRepeats = nil
            closes = true
            points = []
            netTurn = 0
            runDisplacement = .zero
            center = nil
            return
        }

        // One run, walked from the origin facing along +x. The heading is counted
        // in whole turns taken rather than accumulated as an angle, so a long walk
        // does not drift off its own rule.
        var position = Vector2.zero
        var turnsTaken = 0
        for i in 1 ... order {
            position += Vector2(angle: Double(turnsTaken) * turn, length: step * Double(i))
            turnsTaken += reversed.contains(i) ? -1 : 1
        }
        let net = Double(turnsTaken) * turn
        netTurn = net
        runDisplacement = position

        // A whole number of runs closes the ring when it makes a whole number of
        // turns. The displacement cancels on its own then, because the runs are
        // one journey turned by equal steps the whole way around.
        let laps = net / .tau
        let drifts = abs(laps.rounded() - laps) < 1e-9
        var closing: Int?
        if drifts {
            // Every run repeats the same offset, so the walk comes home only if a
            // run goes nowhere at all.
            if position.length < 1e-9 * step * Double(order) { closing = 1 }
        } else {
            for m in 1 ... Swift.max(1, maxRepeats) {
                let turnsMade = Double(m) * laps
                if abs(turnsMade.rounded() - turnsMade) < 1e-9 { closing = m; break }
            }
        }
        closingRepeats = closing
        let runs = Swift.max(1, repeats ?? closing ?? 1)
        self.repeats = runs
        closes = closing.map { runs % $0 == 0 } ?? false

        // The turn that carries one run onto the next has a fixed point, and the
        // whole figure turns about it.
        if drifts {
            center = nil
        } else {
            let c = cos(net), s = sin(net)
            let spread = 2 * (1 - c)
            center = Vector2((1 - c) * position.x - s * position.y,
                             s * position.x + (1 - c) * position.y) / spread
        }

        var walk: [Vector2] = []
        walk.reserveCapacity(order * runs + 1)
        position = .zero
        turnsTaken = 0
        for _ in 0 ..< runs {
            for i in 1 ... order {
                walk.append(position)
                position += Vector2(angle: Double(turnsTaken) * turn, length: step * Double(i))
                turnsTaken += reversed.contains(i) ? -1 : 1
            }
        }
        // A walk that stops away from home keeps the corner it stopped at. One that
        // comes home would only repeat its own first point there.
        if !closes { walk.append(position) }
        points = walk
    }

    // MARK: - Reading it

    /// The walk as a contour, closed when the walk comes home.
    public var contour: Contour { Contour(points, closed: closes && points.count > 2) }

    /// How far the pen travels: `repeats` runs of `1 + 2 + … + order` steps.
    public var length: Double {
        Double(repeats) * step * Double(order * (order + 1)) / 2
    }

    /// One run on its own, as an open contour. The whole figure is this contour
    /// turned about `center`, once per repeat.
    public var run: Contour {
        Contour(Array(points.prefix(order + 1)), closed: false)
    }
}

/// Walk a spirolateral: step 1, 2, 3 … `order` lengths, turning by `turn` after
/// each, and repeat the run until the walk comes home.
///
/// ```swift
/// let figure = spirolateral(order: 7, step: 26)
/// drawPolyline(fitted(figure.points, in: bounds.inset(by: 60)), closed: figure.closes)
/// ```
///
/// With the classic quarter turn, an order that is a multiple of four never
/// closes and every other order closes in `4 / gcd(order, 4)` runs. Turning the
/// other way on some of the steps (`reversed`) changes both the figure and the
/// count.
public func spirolateral(order: Int, turn: Double = .pi / 2, step: Double = 1,
                         reversed: Set<Int> = [], repeats: Int? = nil,
                         maxRepeats: Int = 360) -> Spirolateral {
    Spirolateral(order: order, turn: turn, step: step, reversed: reversed,
                 repeats: repeats, maxRepeats: maxRepeats)
}
