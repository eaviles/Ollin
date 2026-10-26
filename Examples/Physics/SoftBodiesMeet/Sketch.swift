import Foundation
import Ollin
import OllinPhysics

/// Three things a soft body can do when it meets something. On the left a
/// jelly cube sits on a tilted plank: with enough `friction` it holds, and as
/// the parameter drops under the plank's tangent it starts to slide. In the
/// middle a slab of jelly takes whatever lands on it: rigid balls drop onto
/// it every second and a half, and a **click** drops one where the mouse is;
/// each dents the slab, bounces once, and settles, the slab taking its
/// weight. On the right a rope stood on its end buckles and folds onto
/// itself, and stays a rope: the outline is kept out of itself, so the folds
/// lie on each other instead of passing through.
/// **Move the mouse** through anything soft to shove it, and press **space**
/// to set the scene again.
///
/// Every soft thing here is one `addSoftBody(from:)` call; the plank and the
/// balls are rigid `Body`s in the same `World`, and the two sides push each
/// other.
@main
final class SoftBodiesMeet: Sketch {
    let world = World()

    /// How much the jelly on the plank grips it. The plank's tangent is about
    /// 0.42, so the cube holds above that and slides below it.
    @Param(0 ... 1) var friction = 0.8

    /// Whether the rope is kept out of itself. Turn it off and let the scene
    /// reset to watch the folds pass through each other.
    @Param var ropeKeepsOutOfItself = true

    var cube: SoftBody?
    var slab: SoftBody?
    var rope: SoftBody?
    var plank: Body?
    var balls: [Body] = []

    let plankAngle = 0.4
    var plankCenter: Vector2 { Vector2(225, 560) * scale }

    override func setup() throws {
        world.bounds = bounds
        world.drag = 0.015
        world.gravity = Vector2(0, 1400) * scale
        build()
    }

    func build() {
        world.removeAll()
        balls = []

        // The plank, a static rigid body turned to its angle, with a stop at
        // its low end so a sliding cube has somewhere to land.
        let plank = world.addBody(.box(width: 520 * scale, height: 30 * scale), at: plankCenter,
                                  kind: .static, friction: 1)
        plank.angle = plankAngle
        self.plank = plank
        let stop = world.addBody(.box(width: 30 * scale, height: 110 * scale),
                                 at: placed(Vector2(275, -40) * scale, on: plankCenter, angle: plankAngle),
                                 kind: .static, friction: 1)
        stop.angle = plankAngle

        // A cube resting flat on the plank near its high end.
        let seat = placed(Vector2(-150, -15 - 55) * scale, on: plankCenter, angle: plankAngle)
        let side = 110 * scale
        let corners = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
            .map { placed($0 * (side / 2), on: seat, angle: plankAngle) }
        cube = try? world.addSoftBody(from: Shape(corners), mass: 2, spacing: 9 * scale,
                                      shapeMemory: 0.5, friction: friction)

        // A slab of jelly on the floor, rounded at the top corners so a ball
        // rolling to its edge finds a slope rather than a cliff.
        let top = height - 170 * scale
        var outline: [Vector2] = []
        let left = 380 * scale, right = 760 * scale, round = 40 * scale
        outline.append(Vector2(left, height))
        outline.append(Vector2(left, top + round))
        for k in 1 ..< 8 {
            let a = .pi + Double(k) / 8 * .pi / 2
            outline.append(Vector2(left + round, top + round) + Vector2(angle: a, length: round))
        }
        outline.append(Vector2(left + round, top))
        outline.append(Vector2(right - round, top))
        for k in 1 ..< 8 {
            let a = -.pi / 2 + Double(k) / 8 * .pi / 2
            outline.append(Vector2(right - round, top + round) + Vector2(angle: a, length: round))
        }
        outline.append(Vector2(right, top + round))
        outline.append(Vector2(right, height))
        slab = try? world.addSoftBody(from: Shape(outline), mass: 6, spacing: 9 * scale,
                                      shapeMemory: 0.4, friction: 0.6)

        // A rope stood on its end: a long thin outline that buckles under its
        // own weight and folds. Kept out of itself, every fold lies on the
        // one below; a thickness wider than the default keeps the folds
        // chunky enough to read.
        let ropeWidth = 22 * scale, ropeLength = 430 * scale
        let x = 920 * scale
        let ropeShape = Shape([Vector2(x - ropeWidth / 2, height - ropeLength),
                               Vector2(x + ropeWidth / 2, height - ropeLength),
                               Vector2(x + ropeWidth / 2, height),
                               Vector2(x - ropeWidth / 2, height)])
        rope = try? world.addSoftBody(from: ropeShape, mass: 1.5, spacing: 8 * scale, stiffness: 0.95,
                                      bend: 0.6, shapeMemory: 0, friction: 0.7,
                                      collidesWithItself: ropeKeepsOutOfItself, thickness: 9 * scale)
        // A nudge at the top, so the rope leans and folds rather than
        // standing on its end forever.
        for p in rope?.particles ?? [] where p.position.y < height - ropeLength + 50 * scale {
            p.push(Vector2(-1.5, 0) * scale)
        }
    }

    /// Drop a rigid ball at `point`, keeping a dozen at most.
    func drop(at point: Vector2) {
        let ball = world.addBody(.circle(radius: 28 * scale), at: point, density: 2, friction: 0.6,
                                 restitution: 0.1)
        balls.append(ball)
        if balls.count > 12 { world.remove(balls.removeFirst()) }
    }

    override func draw() {
        background(Color(white: 0.09))

        cube?.friction = friction
        if let rope, rope.collidesWithItself != ropeKeepsOutOfItself {
            rope.collidesWithItself = ropeKeepsOutOfItself
        }
        shoveFromCursor()
        // A ball every second and a half, each a little to one side of the
        // last, until six are down.
        if balls.count < 6, frameCount % 90 == 60 {
            let k = Double(balls.count)
            drop(at: Vector2(640 + (k - 2.5) * 30, 60) * scale)
        }
        world.advance(by: deltaTime)

        // The plank and its stop.
        noStroke()
        fill(Color(white: 0.3))
        for body in world.bodies where body.kind == .static {
            withState {
                translate(body.position)
                rotate(body.angle)
                let (w, h) = body === plank ? (520.0, 30.0) : (30.0, 110.0)
                drawRect(center: .zero, width: w * scale, height: h * scale)
            }
        }

        // The soft things, each drawn straight from its outline.
        strokeWeight(2 * scale)
        stroke(Color(white: 0, alpha: 0.3))
        if let cube {
            fill(Color(red: 0.98, green: 0.76, blue: 0.30))
            drawShape(cube.shape)
        }
        if let slab {
            fill(Color(red: 0.36, green: 0.78, blue: 0.72))
            drawShape(slab.shape)
        }
        if let rope {
            fill(Color(red: 0.96, green: 0.44, blue: 0.40))
            drawShape(rope.shape)
        }

        // The balls, from their rigid positions.
        fill(Color(white: 0.92))
        for ball in balls {
            withState {
                translate(ball.position)
                rotate(ball.angle)
                drawCircle(center: .zero, radius: 28 * scale)
                stroke(Color(white: 0.3))
                drawLine(.zero, Vector2(20 * scale, 0))
            }
        }
    }

    override func mousePressed() {
        guard mouseY > 60 * scale else { return }
        drop(at: mouse)
    }

    override func keyPressed() {
        if key == " " { build() }
    }

    /// Push soft particles away from the mouse, falling off with distance.
    func shoveFromCursor() {
        guard mouseX != 0 || mouseY != 0 else { return }
        let reach = 120 * scale
        for body in world.softBodies {
            for p in body.particles {
                let away = p.position - mouse
                let distance = away.length
                guard distance > 0, distance < reach else { continue }
                let falloff = 1 - distance / reach
                p.push(away.normalized * (falloff * falloff * 5 * scale))
            }
        }
    }

    /// A point of a body's own frame placed in the world.
    func placed(_ local: Vector2, on center: Vector2, angle: Double) -> Vector2 {
        center + local.rotated(by: angle)
    }
}
