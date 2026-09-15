import Foundation

/// A crowd of walkers that make room for each other. Every agent wants to go
/// somewhere, and every step each one takes the velocity closest to that wish
/// which keeps it clear of everyone it can see for a few seconds ahead,
/// trusting each neighbor to do half of the avoiding. That trust is the whole
/// model (optimal reciprocal collision avoidance): because both sides of every
/// pair move by half, nobody overcorrects, and a crowd passes through itself
/// without the shoving and oscillation a pushed-apart flock has.
///
/// Hold one, give its agents goals, and `advance(by:)` it each frame:
///
/// ```swift
/// let crowd = Crowd()
///
/// override func setup() {
///     for i in 0 ..< 40 {
///         let angle = Double(i) / 40 * .tau
///         let spot = center + Vector2(angle: angle, length: 400)
///         crowd.add(at: spot, goal: center - (spot - center))
///     }
/// }
///
/// override func draw() {
///     crowd.advance()
///     background(.white)
///     fill(.black)
///     drawCrowd(crowd)
/// }
/// ```
///
/// What it promises, and where the promise ends. An agent looks at its
/// neighbors, works out for each one the half-plane of velocities that keeps
/// the two of them apart for `timeHorizon` seconds if each moves by half, and
/// picks the velocity nearest its preferred one inside every half-plane and
/// under its top speed. Whenever such a velocity exists for every agent, no two
/// agents ever overlap. In a jam (a crowd packed against a door, a knot where
/// streams meet) there may be none; the agent then takes the velocity that
/// intrudes least into the half-planes and is marked `isJammed`, and overlaps
/// of a small part of a radius can happen until the jam loosens. Walls are
/// never relaxed: an agent does not pass through an obstacle, jammed or not.
///
/// Obstacles only keep agents out; they do not route anyone around them. An
/// agent that must reach the far side of a wall needs a goal (or a
/// `preferredVelocity`) that leads it there, such as the door first and the
/// room beyond once it is through.
///
/// Speeds are in points per second and horizons in seconds. A run is a pure
/// function of what was added, the parameters, the seed, and the intervals
/// passed to `advance(by:)`, so it replays exactly.
public final class Crowd {

    /// One walker in a crowd: where it is, where it is going, and how big and
    /// fast it is.
    public struct Agent: Sendable, Equatable {
        /// Where the agent's center is.
        public var position: Vector2
        /// The velocity it took on the last step, in points per second. It
        /// starts at zero; setting it is a shove the agent then corrects.
        public var velocity: Vector2
        /// Where the agent is headed, or `nil` to stand where it is. A
        /// standing agent still steps aside for anyone coming through. Ignored
        /// while the crowd has a `preferredVelocity`.
        public var goal: Vector2?
        /// The agent's radius, in points.
        public var radius: Double
        /// The agent's top speed, in points per second.
        public var maxSpeed: Double
        /// A number of your own for the agent (which door it came in by, which
        /// team it is on), carried untouched and handed to
        /// `preferredVelocity`.
        public var group: Int
        /// Whether no velocity kept the agent clear of every neighbor on the
        /// last step, so it took the one that intrudes least. The mark of a
        /// jam, and the only time two agents can overlap.
        public internal(set) var isJammed: Bool

        /// An agent at `position`, standing still, headed for `goal`.
        public init(at position: Vector2, goal: Vector2? = nil, radius: Double = 8,
                    maxSpeed: Double = 120, group: Int = 0) {
            self.position = position
            self.velocity = .zero
            self.goal = goal
            self.radius = Swift.max(radius, 0)
            self.maxSpeed = Swift.max(maxSpeed, 0)
            self.group = group
            self.isJammed = false
        }
    }

    /// Every agent in the crowd. Read to draw; add, remove, or change agents
    /// between steps as you like.
    public var agents: [Agent] = []

    /// How far ahead an agent looks at other agents, in seconds. A longer
    /// horizon turns earlier and more smoothly but gives up more of each
    /// agent's preferred velocity, and in a dense crowd it can stall everyone
    /// (a ring of 96 crossing to its far side at four seconds stops a third of
    /// the way in); a shorter one walks straighter and swerves later. Every
    /// agent in a crowd shares it, which the half-and-half trust depends on.
    public var timeHorizon: Double
    /// How far ahead an agent looks at obstacles, in seconds. Usually shorter
    /// than `timeHorizon`, so an agent is not shy of a wall it is walking
    /// beside.
    public var obstacleTimeHorizon: Double
    /// How far away another agent can be and still be considered, in points.
    public var perceptionRadius: Double
    /// The most neighbors each agent considers, nearest first.
    public var maxNeighbors: Int
    /// The distance from its goal at which an agent starts to slow down, in
    /// points. 0 walks at full speed until the last step lands on the goal.
    public var slowingRadius: Double = 0
    /// How much each moving agent's preferred velocity is shaken every step,
    /// as a fraction of its top speed. A perfectly symmetric start (a ring of
    /// agents crossing to the far side) otherwise meets in a knot nothing else
    /// can undo, since a jammed agent's choice no longer depends on what it
    /// wants; the shake makes them arrive out of step. The default wanders a
    /// path by less than a point a second at a top speed of 120. 0 turns it off.
    public var jitter: Double = 0.05
    /// The velocity each agent would take with nobody in its way, asked once
    /// for every agent on every step. When set, goals are ignored: use it to
    /// steer by a flow field, send a stream along a corridor, or read `group`.
    public var preferredVelocity: ((Agent) -> Vector2)?

    /// The closed obstacles added, each an outline as it was given.
    public private(set) var obstacles: [[Vector2]] = []
    /// The walls added, each a polyline as it was given.
    public private(set) var walls: [[Vector2]] = []

    private var rng: SplitMix64
    private var corners: [Corner] = []
    private var cornerGrid: [Int64: [Int]] = [:]
    private var cornerCellSize = 64.0
    private var cornersAreStale = false
    private var cornerStamp: [Int] = []
    private var stamp = 0

    /// An empty crowd.
    ///
    /// - Parameters:
    ///   - timeHorizon: How far ahead an agent looks at other agents, in seconds.
    ///   - obstacleTimeHorizon: How far ahead an agent looks at obstacles, in seconds.
    ///   - perceptionRadius: How far away another agent can be and still be considered.
    ///   - maxNeighbors: The most neighbors each agent considers.
    ///   - seed: Picks the jitter, so the same seed replays the same run.
    public init(timeHorizon: Double = 1, obstacleTimeHorizon: Double = 0.5,
                perceptionRadius: Double = 100, maxNeighbors: Int = 10, seed: Int = 0) {
        self.timeHorizon = timeHorizon
        self.obstacleTimeHorizon = obstacleTimeHorizon
        self.perceptionRadius = perceptionRadius
        self.maxNeighbors = maxNeighbors
        self.rng = SplitMix64(seed: UInt64(bitPattern: Int64(seed)))
    }

    /// The number of agents.
    public var count: Int { agents.count }

    /// Add an agent at `position` headed for `goal`, and return its index.
    @discardableResult
    public func add(at position: Vector2, goal: Vector2? = nil, radius: Double = 8,
                    maxSpeed: Double = 120, group: Int = 0) -> Int {
        agents.append(Agent(at: position, goal: goal, radius: radius, maxSpeed: maxSpeed, group: group))
        return agents.count - 1
    }

    // MARK: - Obstacles

    /// Add a closed obstacle, the polygon through `outline`. Either winding
    /// works, and agents are kept outside it. An agent should not start
    /// inside one.
    public func addObstacle(_ outline: [Vector2]) {
        guard outline.count >= 2 else { return }
        obstacles.append(outline)
        var ring = outline
        if ring.count > 2, Crowd.signedArea(ring) < 0 { ring.reverse() }
        appendCorners(ring)
    }

    /// Add a rectangular obstacle.
    public func addObstacle(_ rectangle: Rectangle) {
        addObstacle([rectangle.topLeft, rectangle.topRight, rectangle.bottomRight, rectangle.bottomLeft])
    }

    /// Add a wall along the polyline through `points`: a barrier with no
    /// thickness that agents keep off from either side.
    public func addWall(_ points: [Vector2]) {
        guard points.count >= 2 else { return }
        walls.append(points)
        // Out along the line and back, so each side of every segment faces the
        // agents on that side and every bend is a corner on its outer side.
        appendCorners(points.count == 2 ? points : points + points.dropFirst().dropLast().reversed())
    }

    /// Add a straight wall from `start` to `end`.
    public func addWall(from start: Vector2, to end: Vector2) {
        addWall([start, end])
    }

    /// Remove every obstacle and wall.
    public func removeAllObstacles() {
        obstacles.removeAll()
        walls.removeAll()
        corners.removeAll()
        cornerGrid.removeAll()
        cornersAreStale = false
    }

    // MARK: - Stepping

    /// Advance the crowd by `dt` seconds (one frame at 60 fps by default). The
    /// interval is split into equal steps of at most a sixtieth of a second, and
    /// each step chooses every agent's new velocity from where everyone was
    /// before it moves anyone.
    public func advance(by dt: Double = 1.0 / 60.0) {
        guard dt > 0, !agents.isEmpty else { return }
        if cornersAreStale { indexCorners() }
        let steps = Swift.max(1, Int((dt * 60 - 1e-9).rounded(.up)))
        let h = dt / Double(steps)
        for _ in 0 ..< steps { step(h) }
    }

    private func step(_ h: Double) {
        let n = agents.count
        var preferred = [Vector2](repeating: .zero, count: n)
        for i in 0 ..< n { preferred[i] = wish(of: agents[i], over: h) }

        let reach = Swift.max(perceptionRadius, 1e-6)
        let index = SpatialIndex(agents.map(\.position), cellSize: reach)
        var chosen = [Vector2](repeating: .zero, count: n)
        var jammed = [Bool](repeating: false, count: n)
        var workspace = Workspace()

        for i in 0 ..< n {
            workspace.lines.removeAll(keepingCapacity: true)
            addObstacleLines(for: agents[i], into: &workspace)
            let hardCount = workspace.lines.count
            collectNeighbors(of: i, in: index, reach: reach, into: &workspace)
            addAgentLines(for: i, over: h, into: &workspace)

            var velocity = Vector2.zero
            let failed = Crowd.solve(workspace.lines, maxSpeed: agents[i].maxSpeed,
                                     toward: preferred[i], directional: false, result: &velocity)
            if failed < workspace.lines.count {
                jammed[i] = true
                Crowd.solveLeastIntrusive(workspace.lines, hardCount: hardCount, from: failed,
                                          maxSpeed: agents[i].maxSpeed, scratch: &workspace.projected,
                                          result: &velocity)
            }
            chosen[i] = velocity
        }

        for i in 0 ..< n {
            agents[i].velocity = chosen[i]
            agents[i].isJammed = jammed[i]
            agents[i].position = agents[i].position + chosen[i] * h
        }
    }

    /// Toward the goal at top speed (slowing inside `slowingRadius`, and never
    /// past the goal in one step), or whatever `preferredVelocity` says, then
    /// shaken by `jitter`.
    private func wish(of agent: Agent, over h: Double) -> Vector2 {
        var wish = Vector2.zero
        if let preferredVelocity {
            wish = preferredVelocity(agent)
        } else if let goal = agent.goal {
            let offset = goal - agent.position
            let distance = offset.length
            if distance > 1e-9 {
                var speed = agent.maxSpeed
                if slowingRadius > 0 { speed *= Swift.min(1, distance / slowingRadius) }
                speed = Swift.min(speed, distance / h)
                wish = offset * (speed / distance)
            }
        }
        if jitter > 0, wish.lengthSquared > 1e-18 {
            let angle = Double.random(in: 0 ..< 1, using: &rng) * 2 * .pi
            wish = wish + Vector2(angle: angle, length: jitter * agent.maxSpeed)
        }
        return wish
    }

    // MARK: - Constraints from other agents

    /// The nearest `maxNeighbors` within reach, nearest first, ties by index.
    private func collectNeighbors(of i: Int, in index: SpatialIndex, reach: Double,
                                  into workspace: inout Workspace) {
        workspace.neighbors.removeAll(keepingCapacity: true)
        guard maxNeighbors > 0 else { return }
        let limit = maxNeighbors
        let reach2 = reach * reach
        index.forEachNeighbor(of: i, within: reach) { j, d2 in
            guard d2 < reach2 else { return }
            let entry = (distanceSquared: d2, index: j)
            if workspace.neighbors.count == limit {
                let last = workspace.neighbors[limit - 1]
                guard d2 < last.distanceSquared || (d2 == last.distanceSquared && j < last.index) else { return }
                workspace.neighbors.removeLast()
            }
            var k = workspace.neighbors.count
            workspace.neighbors.append(entry)
            while k > 0 {
                let before = workspace.neighbors[k - 1]
                guard d2 < before.distanceSquared || (d2 == before.distanceSquared && j < before.index) else { break }
                workspace.neighbors[k] = before
                k -= 1
            }
            workspace.neighbors[k] = entry
        }
    }

    /// One half-plane per neighbor: the permitted side of the line through
    /// `velocity + u / 2` perpendicular to `u`, where `u` is the smallest change
    /// to the pair's relative velocity that clears the velocity obstacle (the
    /// disc of both radii seen from the agent, truncated at the time horizon).
    private func addAgentLines(for i: Int, over h: Double, into workspace: inout Workspace) {
        let a = agents[i]
        let inverseHorizon = 1 / Swift.max(timeHorizon, 1e-9)
        for neighbor in workspace.neighbors {
            let b = agents[neighbor.index]
            let offset = b.position - a.position
            let relativeVelocity = a.velocity - b.velocity
            let distance2 = offset.lengthSquared
            let reach = a.radius + b.radius
            let reach2 = reach * reach
            var direction: Vector2
            var u: Vector2

            if distance2 > reach2 {
                // Apart now: clear the truncated cone, through its cap or its legs.
                let w = relativeVelocity - offset * inverseHorizon
                let w2 = w.lengthSquared
                let along = w.dot(offset)
                if along < 0, along * along > reach2 * w2 {
                    let length = w2.squareRoot()
                    let unit = w * (1 / length)
                    direction = Vector2(unit.y, -unit.x)
                    u = unit * (reach * inverseHorizon - length)
                } else {
                    let leg = (distance2 - reach2).squareRoot()
                    if offset.cross(w) > 0 {
                        direction = Vector2(offset.x * leg - offset.y * reach,
                                            offset.x * reach + offset.y * leg) * (1 / distance2)
                    } else {
                        direction = Vector2(-(offset.x * leg + offset.y * reach),
                                            -(-offset.x * reach + offset.y * leg)) * (1 / distance2)
                    }
                    u = direction * relativeVelocity.dot(direction) - relativeVelocity
                }
            } else {
                // Already overlapping: separate within this one step.
                let inverseStep = 1 / h
                let w = relativeVelocity - offset * inverseStep
                let length = w.length
                let unit = length > 1e-12 ? w * (1 / length) : Vector2(-offset.y, offset.x).normalized
                direction = Vector2(unit.y, -unit.x)
                u = unit * (reach * inverseStep - length)
            }
            workspace.lines.append(HalfPlane(point: a.velocity + u * 0.5, direction: direction))
        }
    }

    // MARK: - Constraints from obstacles

    /// One corner of an obstacle: a vertex and the edge leaving it.
    private struct Corner {
        var point: Vector2
        var direction: Vector2
        var next: Int
        var previous: Int
        var isConvex: Bool
    }

    private func appendCorners(_ ring: [Vector2]) {
        let base = corners.count
        let n = ring.count
        for k in 0 ..< n {
            let before = ring[(k + n - 1) % n], here = ring[k], after = ring[(k + 1) % n]
            // Convex when the outline turns toward its inside here; a segment's
            // two ends are both convex.
            let turn = (after - here).cross(here - before)
            corners.append(Corner(point: here, direction: (after - here).normalized,
                                  next: base + (k + 1) % n, previous: base + (k + n - 1) % n,
                                  isConvex: n == 2 || turn <= 0))
        }
        cornersAreStale = true
    }

    /// Bucket every edge into a grid by its bounding box, so an agent reads
    /// only the edges near it.
    private func indexCorners() {
        cornerGrid.removeAll(keepingCapacity: true)
        cornerStamp = [Int](repeating: -1, count: corners.count)
        stamp = 0
        cornerCellSize = Swift.max(perceptionRadius, 16)
        for (k, corner) in corners.enumerated() {
            let end = corners[corner.next].point
            let (x0, y0) = cell(Vector2(Swift.min(corner.point.x, end.x), Swift.min(corner.point.y, end.y)))
            let (x1, y1) = cell(Vector2(Swift.max(corner.point.x, end.x), Swift.max(corner.point.y, end.y)))
            for cx in x0 ... x1 {
                for cy in y0 ... y1 { cornerGrid[Crowd.key(cx, cy), default: []].append(k) }
            }
        }
        cornersAreStale = false
    }

    private func cell(_ p: Vector2) -> (Int, Int) {
        // Clamped, so a point far outside any grid still names a cell.
        func index(_ v: Double) -> Int { Int(Swift.min(Swift.max((v / cornerCellSize).rounded(.down), -1e9), 1e9)) }
        return (index(p.x), index(p.y))
    }

    private static func key(_ x: Int, _ y: Int) -> Int64 {
        (Int64(Int32(truncatingIfNeeded: x)) << 32) | Int64(UInt32(truncatingIfNeeded: y))
    }

    /// The edges within reach that face the agent, nearest first.
    private func nearbyEdges(for agent: Agent, into workspace: inout Workspace) {
        workspace.edges.removeAll(keepingCapacity: true)
        guard !corners.isEmpty else { return }
        let reach = Swift.max(obstacleTimeHorizon, 0) * agent.maxSpeed + agent.radius
        let p = agent.position
        guard reach.isFinite, p.x.isFinite, p.y.isFinite else { return }
        stamp += 1
        let (x0, y0) = cell(Vector2(p.x - reach, p.y - reach))
        let (x1, y1) = cell(Vector2(p.x + reach, p.y + reach))
        // A reach wider than the grid itself reads every bucket once instead.
        if Double(x1 - x0 + 1) * Double(y1 - y0 + 1) > Double(cornerGrid.count) {
            for bucket in cornerGrid.values { gather(bucket, near: p, within: reach, into: &workspace) }
        } else {
            for cx in x0 ... x1 {
                for cy in y0 ... y1 {
                    if let bucket = cornerGrid[Crowd.key(cx, cy)] { gather(bucket, near: p, within: reach, into: &workspace) }
                }
            }
        }
        // Sorted, so the dictionary's order never reaches the outcome.
        workspace.edges.sort { $0.distanceSquared < $1.distanceSquared
            || ($0.distanceSquared == $1.distanceSquared && $0.index < $1.index) }
    }

    private func gather(_ bucket: [Int], near p: Vector2, within reach: Double, into workspace: inout Workspace) {
        for k in bucket where cornerStamp[k] != stamp {
            cornerStamp[k] = stamp
            let a = corners[k].point, b = corners[corners[k].next].point
            let edge = b - a
            // Only an edge's outer side sees it.
            guard (a - p).cross(edge) < 0 else { continue }
            let t = (p - a).dot(edge) / edge.lengthSquared
            let closest = t < 0 ? a : (t > 1 ? b : a + edge * t)
            let d2 = p.distanceSquared(to: closest)
            guard d2 < reach * reach else { continue }
            workspace.edges.append((distanceSquared: d2, index: k))
        }
    }

    /// One half-plane per edge the agent is not already kept from: the agent
    /// takes all of the avoiding (an obstacle does not move), measured against
    /// `obstacleTimeHorizon`, and the line touches the edge's velocity obstacle
    /// where it is nearest zero velocity.
    private func addObstacleLines(for agent: Agent, into workspace: inout Workspace) {
        nearbyEdges(for: agent, into: &workspace)
        guard !workspace.edges.isEmpty else { return }
        let inverseHorizon = 1 / Swift.max(obstacleTimeHorizon, 1e-9)
        let r = agent.radius, r2 = r * r
        let p = agent.position, v = agent.velocity

        for edge in workspace.edges {
            var left = corners[edge.index]
            var right = corners[left.next]
            let toLeft = left.point - p, toRight = right.point - p

            // Already kept off this edge by a line from a nearer one.
            var covered = false
            for line in workspace.lines {
                if (toLeft * inverseHorizon - line.point).cross(line.direction) - inverseHorizon * r >= -Crowd.epsilon,
                   (toRight * inverseHorizon - line.point).cross(line.direction) - inverseHorizon * r >= -Crowd.epsilon {
                    covered = true
                    break
                }
            }
            if covered { continue }

            let leftDistance2 = toLeft.lengthSquared, rightDistance2 = toRight.lengthSquared
            let span = right.point - left.point
            let s = (-toLeft).dot(span) / span.lengthSquared
            let lineDistance2 = (-toLeft - span * s).lengthSquared

            // Touching already: forbid only moving further in.
            if s < 0, leftDistance2 <= r2 {
                if left.isConvex {
                    workspace.lines.append(HalfPlane(point: .zero, direction: Vector2(-toLeft.y, toLeft.x).normalized))
                }
                continue
            }
            if s > 1, rightDistance2 <= r2 {
                if right.isConvex, toRight.cross(right.direction) >= 0 {
                    workspace.lines.append(HalfPlane(point: .zero, direction: Vector2(-toRight.y, toRight.x).normalized))
                }
                continue
            }
            if s >= 0, s <= 1, lineDistance2 <= r2 {
                workspace.lines.append(HalfPlane(point: .zero, direction: -left.direction))
                continue
            }

            // Apart: the two legs of the obstacle's velocity obstacle, both from
            // one corner when the edge is seen end on.
            var leftLeg: Vector2, rightLeg: Vector2
            var oneCorner = false
            if s < 0, lineDistance2 <= r2 {
                guard left.isConvex else { continue }
                right = left
                oneCorner = true
                (leftLeg, rightLeg) = Crowd.tangents(toLeft, r)
            } else if s > 1, lineDistance2 <= r2 {
                guard right.isConvex else { continue }
                left = right
                oneCorner = true
                (leftLeg, rightLeg) = Crowd.tangents(toRight, r)
            } else {
                leftLeg = left.isConvex ? Crowd.tangents(toLeft, r).left : -left.direction
                rightLeg = right.isConvex ? Crowd.tangents(toRight, r).right : left.direction
            }

            // A leg cannot point into the neighboring edge at a convex corner;
            // it follows that edge instead, and a projection onto it adds nothing.
            var leftLegIsForeign = false, rightLegIsForeign = false
            let previousEdge = corners[left.previous]
            if left.isConvex, leftLeg.cross(-previousEdge.direction) >= 0 {
                leftLeg = -previousEdge.direction
                leftLegIsForeign = true
            }
            if right.isConvex, rightLeg.cross(right.direction) <= 0 {
                rightLeg = right.direction
                rightLegIsForeign = true
            }

            // The cutoff: the edge scaled by the horizon, rounded by the radius.
            let leftCutoff = (left.point - p) * inverseHorizon
            let rightCutoff = (right.point - p) * inverseHorizon
            let cutoff = rightCutoff - leftCutoff
            let t = oneCorner ? 0.5 : (v - leftCutoff).dot(cutoff) / cutoff.lengthSquared
            let tLeft = (v - leftCutoff).dot(leftLeg)
            let tRight = (v - rightCutoff).dot(rightLeg)

            if (t < 0 && tLeft < 0) || (oneCorner && tLeft < 0 && tRight < 0) {
                let unit = (v - leftCutoff).normalized
                workspace.lines.append(HalfPlane(point: leftCutoff + unit * (r * inverseHorizon),
                                                 direction: Vector2(unit.y, -unit.x)))
                continue
            }
            if t > 1, tRight < 0 {
                let unit = (v - rightCutoff).normalized
                workspace.lines.append(HalfPlane(point: rightCutoff + unit * (r * inverseHorizon),
                                                 direction: Vector2(unit.y, -unit.x)))
                continue
            }

            let cutoffDistance2 = (t < 0 || t > 1 || oneCorner)
                ? Double.infinity : (v - (leftCutoff + cutoff * t)).lengthSquared
            let leftDistance = tLeft < 0 ? Double.infinity : (v - (leftCutoff + leftLeg * tLeft)).lengthSquared
            let rightDistance = tRight < 0 ? Double.infinity : (v - (rightCutoff + rightLeg * tRight)).lengthSquared

            if cutoffDistance2 <= leftDistance, cutoffDistance2 <= rightDistance {
                let direction = -left.direction
                workspace.lines.append(HalfPlane(point: leftCutoff + direction.perpendicular * (r * inverseHorizon),
                                                 direction: direction))
            } else if leftDistance <= rightDistance {
                guard !leftLegIsForeign else { continue }
                workspace.lines.append(HalfPlane(point: leftCutoff + leftLeg.perpendicular * (r * inverseHorizon),
                                                 direction: leftLeg))
            } else {
                guard !rightLegIsForeign else { continue }
                let direction = -rightLeg
                workspace.lines.append(HalfPlane(point: rightCutoff + direction.perpendicular * (r * inverseHorizon),
                                                 direction: direction))
            }
        }
    }

    /// The two unit directions from the agent that graze a disc of `radius`
    /// around the point at `offset`: the left one and the right one.
    private static func tangents(_ offset: Vector2, _ radius: Double) -> (left: Vector2, right: Vector2) {
        let d2 = offset.lengthSquared
        let leg = Swift.max(d2 - radius * radius, 0).squareRoot()
        let left = Vector2(offset.x * leg - offset.y * radius, offset.x * radius + offset.y * leg) * (1 / d2)
        let right = Vector2(offset.x * leg + offset.y * radius, -offset.x * radius + offset.y * leg) * (1 / d2)
        return (left, right)
    }

    private static func signedArea(_ ring: [Vector2]) -> Double {
        var total = 0.0
        for k in ring.indices { total += ring[k].cross(ring[(k + 1) % ring.count]) }
        return total / 2
    }

    // MARK: - Choosing the velocity

    /// A line in velocity space; velocities on its left (seen along
    /// `direction`) are permitted.
    struct HalfPlane {
        var point: Vector2
        var direction: Vector2
    }

    /// The per-step buffers, reused across agents.
    private struct Workspace {
        var lines: [HalfPlane] = []
        var projected: [HalfPlane] = []
        var neighbors: [(distanceSquared: Double, index: Int)] = []
        var edges: [(distanceSquared: Double, index: Int)] = []
    }

    private static let epsilon = 1e-5

    /// The permitted velocity nearest `target` within `maxSpeed`, adding the
    /// constraints one at a time and moving the answer onto a line only when
    /// the line rules it out (the incremental two-dimensional linear program).
    /// With `directional`, `target` is a unit direction to go as far along as
    /// possible. Returns the index of the first line that could not be met,
    /// or `lines.count` when every line was.
    static func solve(_ lines: [HalfPlane], maxSpeed: Double, toward target: Vector2,
                      directional: Bool, result: inout Vector2) -> Int {
        if directional {
            result = target * maxSpeed
        } else if target.lengthSquared > maxSpeed * maxSpeed {
            result = target.normalized * maxSpeed
        } else {
            result = target
        }
        for i in lines.indices where lines[i].direction.cross(lines[i].point - result) > 0 {
            let kept = result
            if !solve(onLine: i, of: lines, maxSpeed: maxSpeed, toward: target,
                      directional: directional, result: &result) {
                result = kept
                return i
            }
        }
        return lines.count
    }

    /// The best velocity on line `i` within the speed disc and the earlier
    /// lines, or `false` when that stretch of the line is empty.
    private static func solve(onLine i: Int, of lines: [HalfPlane], maxSpeed: Double, toward target: Vector2,
                              directional: Bool, result: inout Vector2) -> Bool {
        let line = lines[i]
        let along = line.point.dot(line.direction)
        let discriminant = along * along + maxSpeed * maxSpeed - line.point.lengthSquared
        guard discriminant >= 0 else { return false }
        let root = discriminant.squareRoot()
        var low = -along - root, high = -along + root

        for j in 0 ..< i {
            let other = lines[j]
            let denominator = line.direction.cross(other.direction)
            let numerator = other.direction.cross(line.point - other.point)
            if abs(denominator) <= epsilon {
                if numerator < 0 { return false }
                continue
            }
            let t = numerator / denominator
            if denominator >= 0 { high = Swift.min(high, t) } else { low = Swift.max(low, t) }
            if low > high { return false }
        }

        if directional {
            result = line.point + line.direction * (target.dot(line.direction) > 0 ? high : low)
        } else {
            let t = line.direction.dot(target - line.point)
            result = line.point + line.direction * Swift.min(Swift.max(t, low), high)
        }
        return true
    }

    /// When no velocity meets every agent line: the velocity inside the speed
    /// disc and every obstacle line that minimizes the largest distance it
    /// sits past any agent line (the three-dimensional program, solved by
    /// projecting onto each violated line in turn).
    static func solveLeastIntrusive(_ lines: [HalfPlane], hardCount: Int, from start: Int,
                                    maxSpeed: Double, scratch projected: inout [HalfPlane],
                                    result: inout Vector2) {
        var depth = 0.0
        for i in start ..< lines.count where lines[i].direction.cross(lines[i].point - result) > depth {
            projected.removeAll(keepingCapacity: true)
            projected.append(contentsOf: lines[0 ..< hardCount])
            // Empty when the line that could not be met is an obstacle's own.
            for j in hardCount ..< Swift.max(hardCount, i) {
                let determinant = lines[i].direction.cross(lines[j].direction)
                var point: Vector2
                if abs(determinant) <= epsilon {
                    // Parallel: the same way adds nothing, the opposite way meets halfway.
                    if lines[i].direction.dot(lines[j].direction) > 0 { continue }
                    point = (lines[i].point + lines[j].point) * 0.5
                } else {
                    point = lines[i].point + lines[i].direction
                        * (lines[j].direction.cross(lines[i].point - lines[j].point) / determinant)
                }
                projected.append(HalfPlane(point: point,
                                           direction: (lines[j].direction - lines[i].direction).normalized))
            }
            let kept = result
            if solve(projected, maxSpeed: maxSpeed, toward: lines[i].direction.perpendicular,
                     directional: true, result: &result) < projected.count {
                // The answer is feasible by construction; a miss here is rounding.
                result = kept
            }
            depth = lines[i].direction.cross(lines[i].point - result)
        }
    }
}

// MARK: - Sketch sugar

public extension Sketch {
    /// Draw every agent of `crowd` as a circle of its radius, with the current
    /// `fill` and `stroke`.
    func drawCrowd(_ crowd: Crowd) {
        for agent in crowd.agents {
            drawCircle(center: agent.position, radius: agent.radius)
        }
    }
}
