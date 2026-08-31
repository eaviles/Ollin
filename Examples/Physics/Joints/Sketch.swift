import Foundation
import Ollin
import OllinPhysics

/// The four `JointKind` cases side by side, one small rig each, all hung from
/// static anchors (`Body.kind = .static`, pieces the solver never moves): a
/// **revolute** pendulum swinging on a free hinge; a **distance** ball on a
/// slightly springy rope; a **weld** tee, two boxes locked into one rigid piece
/// that swings and tumbles together; and a **prismatic** slider that can only
/// travel along its rail, pulled home by a soft distance rod. Each rig is
/// labeled with its case name.
///
/// **Click a moving piece to grab it** (a cursor-drag mouse joint) and fling it
/// around; **click again to let go**. Space resets. Every rig is one
/// `World.connect(_:_:_:)` with a different `JointKind`, and each piece is
/// drawn straight from its `position`/`angle`.
@main
final class Joints: Sketch {
    let world = World()

    /// The dynamic pieces a click can grab.
    var grabbable: [Body] = []
    /// The active cursor-drag joint, if a piece is currently held.
    var held: Joint?
    /// Rope and rod links (the distance joints) drawn as lines between bodies.
    var tethers: [(Body, Body)] = []

    enum Form {
        case peg(Double)
        case ball(Double)
        case capsule(Vector2, Vector2, Double)
        case box(Double, Double)
    }
    final class Look {
        let form: Form
        let color: Color
        init(_ form: Form, _ color: Color) { self.form = form; self.color = color }
    }

    let pegColor = Color(white: 0.45)
    let armColor = Color(red: 0.45, green: 0.77, blue: 0.71)
    let ballColor = Color(red: 0.95, green: 0.49, blue: 0.34)
    let plankColor = Color(red: 0.55, green: 0.57, blue: 0.88)
    let barColor = Color(red: 0.97, green: 0.71, blue: 0.30)
    let sliderColor = Color(red: 0.42, green: 0.72, blue: 0.94)
    let railColor = Color(white: 0.30)

    /// One column per case, left to right in declaration order.
    var columns: [Double] { (0 ..< 4).map { width * (0.125 + 0.25 * Double($0)) } }
    var anchorY: Double { height * 0.46 }

    override func setup() {
        world.gravity = Vector2(0, 2000)
        world.bounds = bounds              // keep flung pieces on-canvas
        build()
        noStroke()
    }

    func build() {
        grabbable.removeAll()
        tethers.removeAll()
        let x = columns
        buildRevolute(at: Vector2(x[0], anchorY))
        buildDistance(at: Vector2(x[1], anchorY))
        buildWeld(at: Vector2(x[2], anchorY))
        buildPrismatic(at: Vector2(x[3], anchorY))
    }

    /// A static anchor peg: the one body in each rig the solver never moves.
    @discardableResult
    func peg(at point: Vector2) -> Body {
        let peg = world.addBody(.circle(radius: 10 * scale), at: point, kind: .static)
        peg.userData = Look(.peg(10 * scale), pegColor)
        return peg
    }

    /// `.revolute`: a capsule arm sharing a free pivot with the peg, started at
    /// a lean so it swings on launch. The plain pendulum.
    func buildRevolute(at top: Vector2) {
        let anchor = peg(at: top)
        let length = 230 * scale
        let unit = Vector2(angle: .pi / 2 - 1.0, length: 1)   // leaned off straight down
        let half = unit * (length * 0.46)
        let arm = world.addBody(.capsule(from: -half, to: half, radius: 12 * scale),
                                at: top + unit * (length * 0.5), density: 1, friction: 0.5)
        arm.userData = Look(.capsule(-half, half, 12 * scale), armColor)
        world.connect(anchor, arm, .revolute(at: top))
        grabbable.append(arm)
    }

    /// `.distance`: a heavy ball held a rope's length from the peg. The low
    /// stiffness softens the rod into a spring, so the ball bobs as it swings.
    func buildDistance(at top: Vector2) {
        let anchor = peg(at: top)
        let drop = Vector2(angle: .pi / 2 + 0.85, length: 235 * scale)
        let ball = world.addBody(.circle(radius: 28 * scale), at: top + drop,
                                 density: 4, friction: 0.5)
        ball.userData = Look(.ball(28 * scale), ballColor)
        world.connect(anchor, ball, .distance(from: top, to: ball.position,
                                              length: nil, stiffness: 0.2))
        grabbable.append(ball)
        tethers.append((anchor, ball))
    }

    /// `.weld`: a plank hinged at the peg, with a crossbar welded to its far
    /// end. The two boxes read as one rigid tee, even flung into a wall.
    func buildWeld(at top: Vector2) {
        let anchor = peg(at: top)
        let lean = -0.65
        let down = Vector2(angle: .pi / 2 + lean, length: 1)
        let plankLength = 180 * scale
        let plank = world.addBody(.box(width: 24 * scale, height: plankLength),
                                  at: top + down * (plankLength * 0.5),
                                  density: 1, friction: 0.5)
        plank.angle = lean
        plank.userData = Look(.box(24 * scale, plankLength), plankColor)
        world.connect(anchor, plank, .revolute(at: top))

        let bar = world.addBody(.box(width: 170 * scale, height: 24 * scale),
                                at: top + down * (plankLength + 12 * scale),
                                density: 1, friction: 0.5)
        bar.angle = lean
        bar.userData = Look(.box(170 * scale, 24 * scale), barColor)
        world.connect(plank, bar, .weld)
        grabbable.append(plank)
        grabbable.append(bar)
    }

    /// `.prismatic`: a box that can only translate along its rail's axis. A
    /// soft distance rod back to the peg is the return spring: its rest length
    /// is the perpendicular drop, so it is satisfied only at the rail's center
    /// and the slider oscillates home when plucked.
    func buildPrismatic(at top: Vector2) {
        let anchor = peg(at: top)
        let railY = top.y + 150 * scale
        let rail = world.addBody(.box(width: 260 * scale, height: 8 * scale),
                                 at: Vector2(top.x, railY), kind: .static)
        rail.userData = Look(.box(260 * scale, 8 * scale), railColor)

        let start = Vector2(top.x - 85 * scale, railY)   // off-center, so it springs back on launch
        let slider = world.addBody(.box(width: 72 * scale, height: 44 * scale), at: start,
                                   density: 1, friction: 0.2)
        slider.userData = Look(.box(72 * scale, 44 * scale), sliderColor)
        world.connect(rail, slider, .prismatic(at: start, axis: Vector2(1, 0)))
        world.connect(anchor, slider, .distance(from: top, to: start,
                                                length: 150 * scale, stiffness: 0.25))
        grabbable.append(slider)
        tethers.append((anchor, slider))
    }

    override func mousePressed() {
        if let held {                       // already holding, so let go
            held.remove()
            self.held = nil
            return
        }
        let cursor = mouse
        var nearest: Body?
        var nearestDistance = 90 * scale    // grab radius
        for body in grabbable {
            let d = body.position.distance(to: cursor)
            if d < nearestDistance { nearestDistance = d; nearest = body }
        }
        if let body = nearest {
            held = world.grab(body, at: cursor)
        }
    }

    override func keyPressed() {
        if key == " " {
            held = nil                      // grab joints are gone with removeAll
            world.removeAll()
            build()
        }
    }

    override func draw() {
        background(Color(white: 0.11))

        held?.target = mouse   // drag the held piece to the cursor
        world.advance(by: deltaTime)

        // Ropes and rods (the distance joints) first, so bodies draw over them.
        stroke(Color(white: 0.8, alpha: 0.5))
        strokeWeight(3 * scale)
        for (a, b) in tethers { drawLine(a.position, b.position) }
        noStroke()

        for body in world.bodies {
            guard let look = body.userData as? Look else { continue }
            withState {
                translate(body.position)
                rotate(body.angle)
                fill(look.color)
                switch look.form {
                case .peg(let r):
                    drawCircle(center: .zero, radius: r)
                case .ball(let r):
                    drawCircle(center: .zero, radius: r)
                case .capsule(let a, let b, let r):
                    stroke(look.color)
                    strokeWeight(2 * r)
                    drawLine(a, b)
                case .box(let w, let h):
                    drawRect(center: .zero, width: w, height: h, cornerRadius: 3 * scale)
                }
            }
        }

        drawLabels()
    }

    /// Each rig's case name, above its anchor.
    func drawLabels() {
        withState {
            textFont(.system)
            textSize(width * 0.021)
            textAlign(.center)
            noStroke()
            fill(Color(white: 0.85))
            for (x, name) in zip(columns, ["revolute", "distance", "weld", "prismatic"]) {
                drawText(".\(name)", at: Vector2(x, height * 0.34))
            }
        }
    }
}
