import Foundation
import Testing
@testable import Ollin

/// Laws of the crowd that makes room (optimal reciprocal collision avoidance):
/// the unobstructed identity, the half-and-half share, no overlap while every
/// agent finds a safe velocity, walls that hold even in a jam, the jam's small
/// overlap, a door's flow against its width, lanes in opposing streams, and a
/// run that replays.
struct CrowdTests {

    // MARK: - Measures

    /// The smallest gap between any two agents' discs; negative is an overlap.
    private func smallestGap(_ crowd: Crowd) -> Double {
        var smallest = Double.infinity
        let agents = crowd.agents
        for i in agents.indices {
            for j in (i + 1) ..< agents.count {
                let gap = agents[i].position.distance(to: agents[j].position) - agents[i].radius - agents[j].radius
                smallest = min(smallest, gap)
            }
        }
        return smallest
    }

    private func distance(from p: Vector2, toSegment a: Vector2, _ b: Vector2) -> Double {
        let edge = b - a
        let t = max(0, min(1, (p - a).dot(edge) / edge.lengthSquared))
        return p.distance(to: a + edge * t)
    }

    /// How far inside the rectangle `p` sits past the agent's own radius:
    /// positive when a disc of `radius` at `p` reaches into it.
    private func intrusion(of p: Vector2, radius: Double, into box: Rectangle) -> Double {
        let dx = max(box.x - p.x, 0, p.x - (box.x + box.width))
        let dy = max(box.y - p.y, 0, p.y - (box.y + box.height))
        if dx == 0, dy == 0 { return radius + min(p.x - box.x, box.x + box.width - p.x, p.y - box.y, box.y + box.height - p.y) }
        return radius - (dx * dx + dy * dy).squareRoot()
    }

    // MARK: - One agent, two agents

    @Test func aLoneAgentWalksAtItsPreferredVelocity() {
        let crowd = Crowd()
        crowd.jitter = 0
        crowd.add(at: Vector2(0, 0), goal: Vector2(300, 400), maxSpeed: 50)
        crowd.advance()
        let expected = Vector2(300, 400).normalized * 50
        #expect(crowd.agents[0].velocity.distance(to: expected) < 1e-12)
        #expect(!crowd.agents[0].isJammed)

        // A wish under the top speed is taken as it is; one over it keeps its
        // direction at the top speed.
        crowd.preferredVelocity = { _ in Vector2(-20, 5) }
        crowd.advance()
        #expect(crowd.agents[0].velocity.distance(to: Vector2(-20, 5)) < 1e-12)
        crowd.preferredVelocity = { _ in Vector2(0, -900) }
        crowd.advance()
        #expect(crowd.agents[0].velocity.distance(to: Vector2(0, -50)) < 1e-12)
    }

    @Test func theLastStepLandsOnTheGoal() {
        let crowd = Crowd()
        crowd.jitter = 0
        crowd.add(at: Vector2(0, 0), goal: Vector2(10, 0), maxSpeed: 120)
        for _ in 0 ..< 10 { crowd.advance() }
        #expect(crowd.agents[0].position.distance(to: Vector2(10, 0)) < 1e-9)
        #expect(crowd.agents[0].velocity.length < 1e-9)
    }

    @Test func twoAgentsHeadOnShareTheSwerveExactly() {
        // The start is symmetric under a half turn, and each agent does half of
        // the avoiding, so each is the other's mirror image at every step: the
        // same swerve, taken in opposite directions.
        let crowd = Crowd()
        crowd.jitter = 0
        crowd.add(at: Vector2(-200, 0), goal: Vector2(200, 0))
        crowd.add(at: Vector2(200, 0), goal: Vector2(-200, 0))
        var widest = 0.0
        for _ in 0 ..< 6 * 60 {
            crowd.advance()
            let a = crowd.agents[0], b = crowd.agents[1]
            #expect(a.position.x == -b.position.x && a.position.y == -b.position.y)
            #expect(smallestGap(crowd) >= -1e-9)
            widest = max(widest, abs(a.position.y))
        }
        #expect(widest > 4)
        #expect(crowd.agents[0].position.distance(to: Vector2(200, 0)) < 1e-6)
        #expect(crowd.agents[1].position.distance(to: Vector2(-200, 0)) < 1e-6)
    }

    @Test func eachSideTakesHalfAndThePairJustGrazes() {
        // Two agents on a collision course that want to keep going as they are.
        // Each moves its velocity by half of the smallest change that clears the
        // collision, in opposite directions, so together their new relative
        // velocity lands exactly on the edge of what collides: followed for the
        // horizon it passes at precisely the sum of the radii.
        let crowd = Crowd(timeHorizon: 2, perceptionRadius: 300)
        crowd.jitter = 0
        crowd.preferredVelocity = { $0.velocity }
        crowd.add(at: Vector2(0, 0))
        crowd.add(at: Vector2(200, 10))
        crowd.agents[0].velocity = Vector2(60, 0)
        crowd.agents[1].velocity = Vector2(-60, 0)
        let offset = Vector2(200, 10)
        crowd.advance()

        let changeA = crowd.agents[0].velocity - Vector2(60, 0)
        let changeB = crowd.agents[1].velocity - Vector2(-60, 0)
        #expect((changeA + changeB).length < 1e-9)
        #expect(changeA.length > 1)

        let relative = crowd.agents[0].velocity - crowd.agents[1].velocity
        let t = min(max(offset.dot(relative) / relative.lengthSquared, 0), crowd.timeHorizon)
        let closestApproach = (offset - relative * t).length
        #expect(abs(closestApproach - 16) < 1e-9)
    }

    @Test func aStandingAgentStepsAside() {
        let crowd = Crowd()
        crowd.jitter = 0
        crowd.add(at: Vector2(0, 1))
        crowd.add(at: Vector2(-300, 0), goal: Vector2(300, 0))
        var closest = Double.infinity
        for _ in 0 ..< 8 * 60 {
            crowd.advance()
            closest = min(closest, smallestGap(crowd))
        }
        #expect(closest >= -1e-9)
        #expect(crowd.agents[0].position.distance(to: Vector2(0, 1)) > 2)
        #expect(crowd.agents[1].position.distance(to: Vector2(300, 0)) < 1e-6)
    }

    // MARK: - The promise and its edge

    /// Two square blocks of agents crossing at right angles.
    private func crossing(spacing: Double, seed: Int = 3) -> Crowd {
        let crowd = Crowd(seed: seed)
        let side = 5
        for row in 0 ..< side {
            for column in 0 ..< side {
                let across = Double(column - side / 2) * spacing
                let along = Double(row) * spacing
                crowd.add(at: Vector2(-260 - along, across), goal: Vector2(400 - along, across), group: 0)
                crowd.add(at: Vector2(across, -260 - along), goal: Vector2(across, 400 - along), group: 1)
            }
        }
        return crowd
    }

    @Test func whileEveryAgentFindsASafeVelocityNoTwoOverlap() {
        // Spread out, nobody jams, and the blocks pass through each other with
        // agents grazing and never overlapping.
        let crowd = crossing(spacing: 100)
        var jams = 0
        var closest = Double.infinity
        for _ in 0 ..< 9 * 60 {
            crowd.advance()
            jams += crowd.agents.filter(\.isJammed).count
            closest = min(closest, smallestGap(crowd))
        }
        #expect(jams == 0)
        #expect(closest >= -1e-9)
        #expect(closest < 1)

        // The counterfactual: walked straight through, the blocks collide.
        let straight = crossing(spacing: 100)
        straight.maxNeighbors = 0
        var straightClosest = Double.infinity
        for _ in 0 ..< 9 * 60 {
            straight.advance()
            straightClosest = min(straightClosest, smallestGap(straight))
        }
        #expect(straightClosest < -8)
    }

    /// A room with a door: a wall across x = 0 made of two rectangles, the
    /// crowd packed on the left, every agent aimed at the door until it is
    /// through and at the far side after.
    private func doorway(width: Double, count: Int, seed: Int = 5) -> (Crowd, walls: [Rectangle]) {
        let crowd = Crowd(seed: seed)
        let half = width / 2
        let walls = [Rectangle(x: -5, y: half, width: 10, height: 400 - half),
                     Rectangle(x: -5, y: -400, width: 10, height: 400 - half)]
        for wall in walls { crowd.addObstacle(wall) }
        var rng = SplitMix64(seed: 42)
        var placed: [Vector2] = []
        while placed.count < count {
            let p = Vector2(-380 + Double.random(in: 0 ..< 1, using: &rng) * 350,
                            -300 + Double.random(in: 0 ..< 1, using: &rng) * 600)
            if placed.allSatisfy({ $0.distance(to: p) > 18 }) { placed.append(p) }
        }
        for p in placed { crowd.add(at: p, radius: 8, maxSpeed: 100) }
        crowd.preferredVelocity = { agent in
            let p = agent.position
            let target = p.x < 5 + agent.radius
                ? Vector2(5 + 2 * agent.radius, max(-half + agent.radius, min(half - agent.radius, p.y)))
                : Vector2(600, p.y)
            return (target - p).normalized * agent.maxSpeed
        }
        return (crowd, walls)
    }

    @Test func wallsHoldEvenInAJam() {
        let (crowd, walls) = doorway(width: 48, count: 100)
        var deepest = -Double.infinity
        var jammedSteps = 0
        for _ in 0 ..< 20 * 60 {
            crowd.advance()
            if crowd.agents.contains(where: \.isJammed) { jammedSteps += 1 }
            for agent in crowd.agents {
                for wall in walls { deepest = max(deepest, intrusion(of: agent.position, radius: agent.radius, into: wall)) }
            }
        }
        #expect(jammedSteps > 60)
        #expect(deepest <= 1e-6)
    }

    @Test func aJamOverlapsByASmallPartOfARadius() {
        let (crowd, _) = doorway(width: 48, count: 100)
        var closest = Double.infinity
        var jammed = 0
        for _ in 0 ..< 20 * 60 {
            crowd.advance()
            jammed += crowd.agents.filter(\.isJammed).count
            closest = min(closest, smallestGap(crowd))
        }
        #expect(jammed > 0)
        #expect(closest > -0.25 * 8)
    }

    @Test func aWiderDoorDrainsFasterAndNoFasterThanItCan() {
        // The steady rate through the door, from the middle half of the
        // crossings, against the most a door could pass: as many files as fit
        // across it, each one agent per diameter walked.
        var rates: [Double] = []
        for width in [64.0, 96.0, 128.0] {
            let (crowd, _) = doorway(width: width, count: 80)
            var crossedAt: [Int: Int] = [:]
            var ids = Array(0 ..< crowd.count)
            crowd.agents = crowd.agents.enumerated().map { index, agent in
                var tagged = agent
                tagged.group = index
                return tagged
            }
            for step in 0 ..< 40 * 60 {
                crowd.advance()
                for agent in crowd.agents where agent.position.x > 0 && crossedAt[agent.group] == nil {
                    crossedAt[agent.group] = step
                }
                if crossedAt.count == crowd.count { break }
            }
            ids = ids.filter { crossedAt[$0] != nil }
            #expect(ids.count == crowd.count)
            let times = crossedAt.values.sorted()
            let low = times.count / 4, high = times.count * 3 / 4
            let rate = Double(high - low) / (Double(times[high] - times[low]) / 60)
            let bound = (width / 16) * (100 / 16)
            #expect(rate < bound)
            rates.append(rate)
        }
        #expect(rates[0] < rates[1] && rates[1] < rates[2])
    }

    @Test func opposingStreamsFormLanes() {
        // A corridor fed from both ends. Lane order (for each agent in the
        // middle, the squared balance of same-way against other-way neighbors in
        // its own file) is 1 when every file runs one way. Read against the same
        // positions with the directions shuffled, which is what no lanes looks
        // like at this density.
        let crowd = Crowd(seed: 9)
        let half = 110.0, length = 420.0, speed = 80.0
        crowd.addObstacle(Rectangle(x: -length - 80, y: half, width: 2 * length + 160, height: 20))
        crowd.addObstacle(Rectangle(x: -length - 80, y: -half - 20, width: 2 * length + 160, height: 20))
        crowd.preferredVelocity = { agent in Vector2(agent.group == 0 ? speed : -speed, 0) }
        var rng = SplitMix64(seed: 17)
        var owed = [0.0, 0.0]
        var ordered: [Double] = [], shuffled: [Double] = []

        func laneOrder(_ direction: (Int) -> Int) -> Double {
            let agents = crowd.agents
            var total = 0.0, counted = 0
            for i in agents.indices where abs(agents[i].position.x) < 220 {
                var same = 0, other = 0
                for j in agents.indices where j != i {
                    let offset = agents[j].position - agents[i].position
                    guard abs(offset.y) < 8, abs(offset.x) < 100 else { continue }
                    if direction(j) == direction(i) { same += 1 } else { other += 1 }
                }
                guard same + other > 0 else { continue }
                let balance = Double(same - other) / Double(same + other)
                total += balance * balance
                counted += 1
            }
            return counted > 0 ? total / Double(counted) : 0
        }

        for step in 0 ..< 30 * 60 {
            for side in 0 ..< 2 {
                owed[side] += 8.0 / 60
                while owed[side] >= 1 {
                    owed[side] -= 1
                    let p = Vector2(side == 0 ? -length : length,
                                    -half + 9 + Double.random(in: 0 ..< 1, using: &rng) * (2 * half - 18))
                    if crowd.agents.allSatisfy({ $0.position.distance(to: p) > 17 }) {
                        crowd.add(at: p, radius: 8, maxSpeed: speed, group: side)
                    }
                }
            }
            crowd.agents.removeAll { $0.group == 0 ? $0.position.x > length : $0.position.x < -length }
            crowd.advance()
            if step >= 10 * 60, step % 30 == 0 {
                ordered.append(laneOrder { crowd.agents[$0].group })
                var mixed = crowd.agents.map(\.group)
                mixed.shuffle(using: &rng)
                shuffled.append(laneOrder { mixed[$0] })
            }
        }
        let order = ordered.reduce(0, +) / Double(ordered.count)
        let baseline = shuffled.reduce(0, +) / Double(shuffled.count)
        #expect(order > 0.9)
        #expect(baseline < 0.65)
    }

    // MARK: - Walls and obstacles

    @Test func aWallHoldsFromEitherSide() {
        let crowd = Crowd()
        crowd.jitter = 0
        crowd.addWall(from: Vector2(-100, 0), to: Vector2(100, 0))
        crowd.add(at: Vector2(10, -120), goal: Vector2(10, 200))
        crowd.add(at: Vector2(-30, 120), goal: Vector2(-30, -200))
        for _ in 0 ..< 5 * 60 {
            crowd.advance()
            #expect(crowd.agents[0].position.y <= -crowd.agents[0].radius + 1e-9)
            #expect(crowd.agents[1].position.y >= crowd.agents[1].radius - 1e-9)
        }
    }

    @Test func aBentWallHoldsInsideItsBend() {
        // A wall bent into a V, walked into from the inside of the bend, where
        // both of its segments are close at once.
        let crowd = Crowd()
        crowd.jitter = 0
        let points = [Vector2(-120, -120), Vector2(0, 0), Vector2(120, -120)]
        crowd.addWall(points)
        crowd.add(at: Vector2(0, -150), goal: Vector2(0, 100))
        crowd.add(at: Vector2(30, -160), goal: Vector2(40, 100))
        for _ in 0 ..< 6 * 60 {
            crowd.advance()
            for agent in crowd.agents {
                #expect(distance(from: agent.position, toSegment: points[0], points[1]) >= agent.radius - 1e-9)
                #expect(distance(from: agent.position, toSegment: points[1], points[2]) >= agent.radius - 1e-9)
                #expect(agent.position.y < 0)
            }
        }
    }

    @Test func anAgentWedgedBetweenTwoWallsStaysBetweenThem() {
        // Wider than the slot it stands in, so both walls already touch it and
        // their own lines are the ones that cannot all be met; pressed from
        // behind by a second agent it must neither cross a wall nor stop the run.
        let crowd = Crowd()
        crowd.jitter = 0
        crowd.addWall(from: Vector2(-2000, -6), to: Vector2(2000, -6))
        crowd.addWall(from: Vector2(-2000, 6), to: Vector2(2000, 6))
        crowd.add(at: Vector2(0, 0), goal: Vector2(0, 300))
        crowd.add(at: Vector2(-40, 0), goal: Vector2(300, 40))
        crowd.agents[0].velocity = Vector2(0, 90)
        for _ in 0 ..< 3 * 60 {
            crowd.advance()
            for agent in crowd.agents {
                #expect(agent.position.x.isFinite && agent.position.y.isFinite)
                #expect(abs(agent.position.y) < 6)
            }
        }
    }

    @Test func obstacleLinesThatCannotAllBeMetStillGiveAVelocity() {
        // Two obstacle lines asking for opposite things (at least 50 up, at least
        // 50 down): the first program fails on an obstacle's own line, and the
        // fallback must still hand back a velocity within the top speed.
        let lines = [Crowd.HalfPlane(point: Vector2(0, 50), direction: Vector2(1, 0)),
                     Crowd.HalfPlane(point: Vector2(0, -50), direction: Vector2(-1, 0))]
        var velocity = Vector2.zero
        let failed = Crowd.solve(lines, maxSpeed: 100, toward: Vector2(30, 0), directional: false, result: &velocity)
        #expect(failed == 1)
        var scratch: [Crowd.HalfPlane] = []
        Crowd.solveLeastIntrusive(lines, hardCount: 2, from: failed, maxSpeed: 100, scratch: &scratch, result: &velocity)
        #expect(velocity.x.isFinite && velocity.y.isFinite)
        #expect(velocity.length <= 100 + 1e-9)
    }

    @Test func eitherWindingIsTheSameObstacle() {
        func run(_ outline: [Vector2]) -> [Crowd.Agent] {
            let crowd = Crowd(seed: 2)
            crowd.addObstacle(outline)
            for k in 0 ..< 12 { crowd.add(at: Vector2(-250, Double(k - 6) * 22), goal: Vector2(250, Double(k - 6) * 18)) }
            for _ in 0 ..< 4 * 60 { crowd.advance() }
            return crowd.agents
        }
        let square = [Vector2(-40, -60), Vector2(40, -60), Vector2(40, 60), Vector2(-40, 60)]
        let agents = run(square)
        #expect(agents == run(square.reversed()))
        let box = Rectangle(x: -40, y: -60, width: 80, height: 120)
        for agent in agents { #expect(intrusion(of: agent.position, radius: agent.radius, into: box) <= 1e-6) }
    }

    // MARK: - Replay

    @Test func aRunReplaysExactly() {
        func run(seed: Int) -> [Crowd.Agent] {
            let (crowd, _) = doorway(width: 64, count: 40, seed: seed)
            for _ in 0 ..< 3 * 60 { crowd.advance() }
            return crowd.agents
        }
        #expect(run(seed: 1) == run(seed: 1))
        #expect(run(seed: 1) != run(seed: 2))
    }

    @Test func aLongerIntervalIsTheSameSteps() {
        let a = crossing(spacing: 30)
        let b = crossing(spacing: 30)
        for _ in 0 ..< 120 { a.advance(by: 1.0 / 30.0) }
        for _ in 0 ..< 240 { b.advance(by: 1.0 / 60.0) }
        #expect(a.agents == b.agents)
    }
}
