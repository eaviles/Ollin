// figure: frame=150 themed
//
// Guide diagram (Chapter 11): what a soft body does when it meets something.
// Two jelly cubes on one tilted plank, the grippy one holding where it was
// put and the slick one slid down to the stop; a rigid ball resting in the
// dent it made in a slab of jelly; and a rope that stood on its end, buckled,
// and folded onto itself without passing through its own side.
import Ollin
import OllinDiagram
import OllinPhysics

final class SoftBodiesMeet: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    let panel = Rectangle(x: 50, y: 40, width: 780, height: 420)
    let plankAngle = 0.38

    var world = World()
    var jellies: [(body: SoftBody, grippy: Bool)] = []
    var rope: SoftBody?
    var ball: Body?
    var planks: [(body: Body, width: Double, height: Double)] = []

    override func setup() throws {
        world = World()
        jellies = []
        planks = []
        world.gravity = Vector2(0, 2000)
        world.bounds = panel

        // The plank and its stop, static rigid bodies.
        let plankCenter = Vector2(panel.x + 190, panel.y + 250)
        let plank = world.addBody(.box(width: 330, height: 22), at: plankCenter, kind: .static, friction: 1)
        plank.angle = plankAngle
        planks.append((plank, 330, 22))
        let stopAt = plankCenter + Vector2(175, -30).rotated(by: plankAngle)
        let stop = world.addBody(.box(width: 22, height: 80), at: stopAt, kind: .static, friction: 1)
        stop.angle = plankAngle
        planks.append((stop, 22, 80))

        // Two cubes side by side near the high end: the first grips, the
        // second does not.
        for (k, grippy) in [true, false].enumerated() {
            let seat = plankCenter + Vector2(-120 + Double(k) * 90, -11 - 36).rotated(by: plankAngle)
            let corners = [Vector2(-36, -36), Vector2(36, -36), Vector2(36, 36), Vector2(-36, 36)]
                .map { seat + $0.rotated(by: plankAngle) }
            let body = try world.addSoftBody(from: Shape(corners), mass: 2, spacing: 6, shapeMemory: 0.5,
                                             friction: grippy ? 1 : 0)
            jellies.append((body, grippy))
        }

        // A slab on the floor and a ball dropped onto it.
        let top = panel.y + panel.height - 90
        let slab = Shape([Vector2(panel.x + 390, top), Vector2(panel.x + 590, top),
                          Vector2(panel.x + 590, panel.y + panel.height),
                          Vector2(panel.x + 390, panel.y + panel.height)])
        jellies.append((try world.addSoftBody(from: slab, mass: 3, spacing: 6, stiffness: 0.6,
                                              shapeMemory: 0.12), true))
        ball = world.addBody(.circle(radius: 26), at: Vector2(panel.x + 490, panel.y + 120), density: 10,
                             friction: 0.6, restitution: 0)

        // A rope stood on end at the right, nudged so it folds.
        let x = panel.x + 700
        let ropeShape = Shape([Vector2(x - 9, panel.y + 120), Vector2(x + 9, panel.y + 120),
                               Vector2(x + 9, panel.y + panel.height), Vector2(x - 9, panel.y + panel.height)])
        let rope = try world.addSoftBody(from: ropeShape, mass: 1.5, spacing: 6, stiffness: 0.95, bend: 0.6,
                                         shapeMemory: 0, friction: 0.7, collidesWithItself: true, thickness: 7)
        for p in rope.particles where p.position.y < panel.y + 160 { p.push(Vector2(-1.2, 0)) }
        self.rope = rope
    }

    override func draw() {
        background(theme.paper)
        world.advance(by: deltaTime)

        noFill()
        stroke(theme.ink(0.12))
        strokeWeight(2)
        drawRect(panel)

        noStroke()
        fill(theme.ink(0.35))
        for plank in planks {
            withState {
                translate(plank.body.position)
                rotate(plank.body.angle)
                drawRect(center: .zero, width: plank.width, height: plank.height)
            }
        }

        strokeWeight(2)
        stroke(theme.ink)
        for jelly in jellies {
            fill(jelly.grippy ? theme.accent : theme.ink(0.14))
            drawShape(jelly.body.shape)
        }
        if let rope {
            fill(theme.ink(0.14))
            drawShape(rope.shape)
        }
        if let ball {
            fill(theme.paper)
            withState {
                translate(ball.position)
                rotate(ball.angle)
                drawCircle(center: .zero, radius: 26)
                drawLine(.zero, Vector2(18, 0))
            }
        }

        noStroke()
        fill(theme.ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("one cube grips and one slides; a ball dents the slab; a rope folds on itself", width / 2, 490)
    }
}
