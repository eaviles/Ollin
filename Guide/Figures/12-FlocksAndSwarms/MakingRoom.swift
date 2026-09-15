// figure: frame=0 themed
//
// Guide figure (Chapter 12): a crowd that makes room. Top left, two walkers
// head on, the path of each center around the line they would have walked, both
// discs where they pass: each swerves by the same amount the other way, because
// each takes half. Top right, a room draining through a door four seconds in, the
// walkers who found no safe velocity this step marked in the accent. Below, a
// corridor fed from both ends for twenty seconds, one direction in ink and the
// other in the accent, drawn over its last second and a half so the lanes it
// sorted itself into read as bands. Every
// run is seeded, so the picture is the same every time.
import Foundation
import Ollin
import OllinDiagram

final class MakingRoom: Sketch {
    override var canvasSize: CanvasSize { .size(880, 520) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    private let zoom = 0.8
    private let headOnPanel = Rectangle(x: 20, y: 50, width: 410, height: 210)
    private let doorPanel = Rectangle(x: 450, y: 50, width: 410, height: 210)
    private let corridorPanel = Rectangle(x: 20, y: 310, width: 840, height: 120)

    private var traces: [[Vector2]] = [[], []]
    private var passing: [Vector2] = []
    private var room: [Crowd.Agent] = []
    private var roomWalls: [[Vector2]] = []
    private var corridor: [Crowd.Agent] = []
    /// Where every walker in the corridor was over its last second and a half.
    private var exposure: [(position: Vector2, group: Int)] = []

    override func setup() {
        runHeadOn()
        runDoorway()
        runCorridor()
    }

    /// Two walkers crossing a 512 by 262 world: every center they pass through,
    /// and the step where they are closest.
    private func runHeadOn() {
        let crowd = Crowd()
        crowd.jitter = 0
        crowd.add(at: Vector2(40, 131), goal: Vector2(472, 131), radius: 14, maxSpeed: 120)
        crowd.add(at: Vector2(472, 131), goal: Vector2(40, 131), radius: 14, maxSpeed: 120)
        var closest = Double.infinity
        for _ in 0 ... 240 {
            for k in 0 ..< 2 { traces[k].append(crowd.agents[k].position) }
            let gap = crowd.agents[0].position.distance(to: crowd.agents[1].position)
            if gap < closest {
                closest = gap
                passing = crowd.agents.map(\.position)
            }
            crowd.advance()
        }
    }

    /// Ninety walkers in the left half of a 512 by 262 room, a door of 56 in the
    /// wall across its middle, each aimed at the middle of the doorway until it is
    /// through.
    private func runDoorway() {
        let crowd = Crowd(seed: 4)
        let door = 56.0, wallX = 250.0, thickness = 12.0
        let top = Rectangle(x: wallX, y: -20, width: thickness, height: 131 - door / 2 + 20)
        let bottom = Rectangle(x: wallX, y: 131 + door / 2, width: thickness, height: 131 - door / 2 + 20)
        crowd.addObstacle(top)
        crowd.addObstacle(bottom)
        var rng = SplitMix64(seed: 11)
        while crowd.count < 90 {
            let p = Vector2(16 + Double.random(in: 0 ..< 1, using: &rng) * 210,
                            12 + Double.random(in: 0 ..< 1, using: &rng) * 238)
            if crowd.agents.allSatisfy({ $0.position.distance(to: p) > 19 }) {
                crowd.add(at: p, radius: 8, maxSpeed: 90)
            }
        }
        crowd.preferredVelocity = { agent in
            let p = agent.position
            let target = p.x < wallX ? Vector2(wallX + thickness / 2, 131) : Vector2(900, p.y)
            return (target - p).normalized * agent.maxSpeed
        }
        for _ in 0 ..< 6 * 60 { crowd.advance() }
        room = crowd.agents
        roomWalls = crowd.obstacles
    }

    /// A corridor 1050 by 150 fed from both ends, run for twenty seconds, the
    /// last second and a half kept.
    private func runCorridor() {
        let crowd = Crowd(seed: 6)
        let length = 1050.0, height = 150.0, speed = 90.0
        crowd.addObstacle(Rectangle(x: -100, y: -20, width: length + 200, height: 20))
        crowd.addObstacle(Rectangle(x: -100, y: height, width: length + 200, height: 20))
        crowd.preferredVelocity = { agent in Vector2(agent.group == 0 ? speed : -speed, 0) }
        var rng = SplitMix64(seed: 21)
        var owed = [0.0, 0.0]
        let frames = 20 * 60
        for frame in 0 ..< frames {
            for side in 0 ..< 2 {
                owed[side] += 9.0 / 60
                while owed[side] >= 1 {
                    owed[side] -= 1
                    let p = Vector2(side == 0 ? -8 : length + 8, 9 + Double.random(in: 0 ..< 1, using: &rng) * (height - 18))
                    if crowd.agents.allSatisfy({ $0.position.distance(to: p) > 17 }) {
                        crowd.add(at: p, radius: 8, maxSpeed: speed, group: side)
                    }
                }
            }
            crowd.agents.removeAll { $0.position.x < -20 || $0.position.x > length + 20 }
            crowd.advance()
            if frame >= frames - 90, frame % 3 == 0 {
                exposure.append(contentsOf: crowd.agents.map { ($0.position, $0.group) })
            }
        }
        corridor = crowd.agents
    }

    override func draw() {
        background(theme.paper)

        // Two walkers: the line they would have walked, the path each took, and
        // both discs at the moment they pass.
        diagramFrame(headOnPanel, title: "two walkers, head on", theme: theme)
        withClip(headOnPanel) {
            stroke(theme.ink(0.3))
            strokeWeight(1.5)
            for x in stride(from: 8.0, to: 504, by: 16) {
                drawLine(place(Vector2(x, 131), in: headOnPanel), place(Vector2(x + 8, 131), in: headOnPanel))
            }
            let colors = [theme.ink, theme.accent]
            noFill()
            strokeWeight(3)
            for k in 0 ..< 2 {
                stroke(colors[k])
                drawPolyline(traces[k].map { place($0, in: headOnPanel) })
            }
            noStroke()
            for k in 0 ..< 2 {
                fill(k == 0 ? theme.ink(0.18) : theme.accent(0.25))
                drawCircle(center: place(traces[k][0], in: headOnPanel), radius: 14 * zoom)
                fill(colors[k])
                drawCircle(center: place(passing[k], in: headOnPanel), radius: 14 * zoom)
            }
        }
        caption("each swerves the same amount", under: headOnPanel)

        // The room: walls, walkers, and the jammed ones in the accent.
        diagramFrame(doorPanel, title: "a room with one door", theme: theme)
        withClip(doorPanel) {
            noStroke()
            fill(theme.ink(0.8))
            for wall in roomWalls { drawPolygon(wall.map { place($0, in: doorPanel) }) }
            for agent in room {
                fill(agent.isJammed ? theme.accent : theme.ink(0.35))
                drawCircle(center: place(agent.position, in: doorPanel), radius: agent.radius * zoom)
            }
        }
        caption("orange: no safe velocity this step", under: doorPanel)

        // The corridor as a short exposure: where everyone was over the last
        // second and a half as faint dots, so a file reads as a band, and each
        // walker now on top, each direction its own color.
        diagramFrame(corridorPanel, title: "a corridor fed from both ends", theme: theme)
        withClip(corridorPanel) {
            noStroke()
            for mark in exposure {
                fill(mark.group == 0 ? theme.ink(0.1) : theme.accent(0.14))
                drawCircle(center: place(mark.position, in: corridorPanel), radius: 3)
            }
            for agent in corridor {
                fill(agent.group == 0 ? theme.ink(0.7) : theme.accent)
                drawCircle(center: place(agent.position, in: corridorPanel), radius: agent.radius * zoom)
            }
        }
        caption("right in gray, left in orange: lanes nobody asked for", under: corridorPanel)

        diagramCaption("each takes half the swerve, and the crowd sorts itself", at: 476, theme: theme)
    }

    private func place(_ p: Vector2, in panel: Rectangle) -> Vector2 {
        Vector2(panel.x + p.x * zoom, panel.y + p.y * zoom)
    }

    private func caption(_ text: String, under panel: Rectangle) {
        drawText(text, panel.x + panel.width / 2, panel.y + panel.height + 10,
                 size: 13, color: theme.muted, align: .center, .top)
    }
}
