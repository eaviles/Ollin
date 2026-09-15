import Foundation
import Ollin

/// A crowd that makes room: every walker heads where it wants to go and takes
/// the velocity nearest that wish which keeps it clear of everyone it can see for
/// the next couple of seconds, trusting each neighbor to do half of the avoiding
/// (`Crowd`). Four scenes: a room draining through a door, a corridor fed from
/// both ends where opposing streams sort themselves into lanes, four streams
/// crossing in a square, and the classic ring of walkers crossing to the far
/// side. A walker ringed in orange is jammed this frame: no velocity kept it
/// clear of everyone, so it took the one that intrudes least. `Horizon` is how
/// far ahead they look; `Door` is the doorway's width; `Rate` is how many
/// walkers enter the corridor from each end every second (half that for each
/// of the four crossing streams).
@main
final class Crowds: Sketch {

    enum Scene: String, CaseIterable, ParamOption {
        case doorway, corridor, crossing, ring
    }

    @Param(icon: "figure.walk", group: "Scene") var scene: Scene = .doorway
    /// How far ahead a walker looks at the others, in seconds.
    @Param("Horizon", 0.25 ... 4, icon: "eye", group: "Walkers") var horizon = 1.0
    /// The doorway's width, in points.
    @Param("Door", 24 ... 220, icon: "door.left.hand.open", group: "Doorway") var door = 90.0
    /// Walkers entering the corridor from each end every second.
    @Param("Rate", 1 ... 24, icon: "arrow.right.to.line", group: "Streams") var rate = 12.0

    private var crowd = Crowd()
    private var builtScene: Scene?
    private var builtDoor = -1.0
    private var owed: [Double] = []
    private let radius = 9.0
    private let speed = 110.0
    private let wall = 18.0
    private let corridor = 260.0
    private let ground = Color(hex: 0x0F1115)
    private let stone = Color(hex: 0x3A3F4B)
    private let jam = Color(hex: 0xFF7A3D)
    private let palette = [Color(hex: 0x6FD3FF), Color(hex: 0xF2E394), Color(hex: 0xC792EA), Color(hex: 0x8BE9A8)]

    override func setup() {
        randomSeed(variation)
        background(ground)
        noClear()
    }

    override func draw() {
        if builtScene != scene { build() }
        if scene == .doorway, door != builtDoor { placeDoorway() }
        crowd.timeHorizon = horizon

        switch scene {
        case .doorway: recycleThroughTheDoor()
        case .corridor, .crossing: feedStreams()
        case .ring: turnTheRingAround()
        }
        crowd.advance()

        // A translucent sheet over the kept canvas, so every walker leaves a short
        // fading trail and a still shows which way the crowd is moving.
        noStroke()
        fill(ground.withAlpha(0.2))
        drawRect(0, 0, width, height)
        fill(stone)
        for outline in crowd.obstacles { drawPolygon(outline) }
        for agent in crowd.agents { drawWalker(agent) }

        fill(ground)
        drawRect(0, height - 56, width, 56)
        let jammed = crowd.agents.filter(\.isJammed).count
        drawCaption(String(format: "Crowd · %@ · %d walking · %d jammed · looking %.1f s ahead",
                           scene.rawValue, crowd.count, jammed, horizon))
    }

    private func drawWalker(_ agent: Crowd.Agent) {
        let tint = palette[agent.group % palette.count]
        if agent.isJammed {
            fill(jam)
            drawCircle(center: agent.position, radius: agent.radius + 2.5)
        }
        fill(tint)
        drawCircle(center: agent.position, radius: agent.radius)
        let speedNow = agent.velocity.length
        if speedNow > 1 {
            fill(ground.withAlpha(0.55))
            drawCircle(center: agent.position + agent.velocity * (agent.radius * 0.45 / speedNow),
                       radius: agent.radius * 0.32)
        }
    }

    // MARK: - Scenes

    private func build() {
        builtScene = scene
        builtDoor = -1
        background(ground)
        crowd = Crowd(seed: variation)
        owed = [0, 0, 0, 0]
        switch scene {
        case .doorway:
            placeDoorway()
            for _ in 0 ..< 220 {
                spawn(in: Rectangle(x: 30, y: 60, width: width / 2 - 90, height: height - 120), group: Int(random(0, 4)))
            }
            crowd.preferredVelocity = { [weak self] agent in self?.throughTheDoor(agent) ?? .zero }
        case .corridor:
            let top = height / 2 - corridor / 2, bottom = height / 2 + corridor / 2
            crowd.addObstacle(Rectangle(x: -200, y: top - wall, width: width + 400, height: wall))
            crowd.addObstacle(Rectangle(x: -200, y: bottom, width: width + 400, height: wall))
            crowd.preferredVelocity = { [speed] agent in Vector2(agent.group == 0 ? speed : -speed, 0) }
        case .crossing:
            crowd.preferredVelocity = { [speed] agent in Crowds.heading(agent.group) * speed }
        case .ring:
            let middle = Vector2(width / 2, height / 2)
            for k in 0 ..< 96 {
                let spot = middle + Vector2(angle: Double(k) / 96 * .tau, length: 440)
                crowd.add(at: spot, goal: middle - (spot - middle), radius: radius, maxSpeed: speed, group: k * 4 / 96)
            }
            crowd.preferredVelocity = nil
        }
    }

    /// Two slabs across the middle with a gap of `door` between them.
    private func placeDoorway() {
        builtDoor = door
        crowd.removeAllObstacles()
        let x = width / 2 - wall / 2, gapTop = height / 2 - door / 2, gapBottom = height / 2 + door / 2
        crowd.addObstacle(Rectangle(x: x, y: -40, width: wall, height: gapTop + 40))
        crowd.addObstacle(Rectangle(x: x, y: gapBottom, width: wall, height: height - gapBottom + 40))
    }

    /// The door until through it, then straight on to the right edge.
    private func throughTheDoor(_ agent: Crowd.Agent) -> Vector2 {
        let p = agent.position
        let beyond = width / 2 + wall / 2 + agent.radius
        let half = door / 2 - agent.radius
        let target = p.x < beyond
            ? Vector2(beyond + agent.radius, min(max(p.y, height / 2 - max(half, 0)), height / 2 + max(half, 0)))
            : Vector2(width + 200, p.y)
        let offset = target - p
        return offset.length > 1e-9 ? offset.normalized * agent.maxSpeed : .zero
    }

    /// A walker who reaches the right edge comes back in at the left.
    private func recycleThroughTheDoor() {
        let arrived = crowd.agents.filter { $0.position.x > width + $0.radius }.count
        crowd.agents.removeAll { $0.position.x > width + $0.radius }
        for _ in 0 ..< arrived { spawn(in: Rectangle(x: 20, y: 60, width: 120, height: height - 120), group: Int(random(0, 4))) }
    }

    nonisolated private static func heading(_ group: Int) -> Vector2 {
        [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)][group % 4]
    }

    /// New walkers at each stream's entrance, and leavers taken away.
    private func feedStreams() {
        let streams = scene == .corridor ? 2 : 4
        let top = height / 2 - corridor / 2 + radius + 1, span = corridor - 2 * radius - 2
        for stream in 0 ..< streams {
            // Four streams share the square, so each carries half the rate.
            owed[stream] += (scene == .corridor ? rate : rate / 2) / 60
            while owed[stream] >= 1 {
                owed[stream] -= 1
                let spot: Vector2
                if scene == .corridor {
                    spot = Vector2(stream == 0 ? -radius : width + radius, top + random(0, span))
                } else {
                    let across = width / 2 + random(-150, 150)
                    spot = [Vector2(-radius, across), Vector2(across, -radius),
                            Vector2(width + radius, across), Vector2(across, height + radius)][stream]
                }
                if crowd.agents.allSatisfy({ $0.position.distance(to: spot) > 2 * radius + 1 }) {
                    crowd.add(at: spot, radius: radius, maxSpeed: speed, group: scene == .corridor ? stream * 2 : stream)
                }
            }
        }
        crowd.agents.removeAll { agent in
            let p = agent.position
            return p.x < -3 * radius || p.x > width + 3 * radius || p.y < -3 * radius || p.y > height + 3 * radius
        }
    }

    /// Once everyone is home, send them all back.
    private func turnTheRingAround() {
        let home = crowd.agents.allSatisfy { agent in
            guard let goal = agent.goal else { return true }
            return agent.position.distance(to: goal) < 2
        }
        guard home else { return }
        let middle = Vector2(width / 2, height / 2)
        for i in crowd.agents.indices {
            crowd.agents[i].goal = middle - (crowd.agents[i].position - middle)
        }
    }

    private func spawn(in box: Rectangle, group: Int) {
        for _ in 0 ..< 40 {
            let spot = Vector2(random(box.x, box.x + box.width), random(box.y, box.y + box.height))
            if crowd.agents.allSatisfy({ $0.position.distance(to: spot) > 2 * radius + 1 }) {
                crowd.add(at: spot, radius: radius, maxSpeed: speed, group: group)
                return
            }
        }
    }
}
