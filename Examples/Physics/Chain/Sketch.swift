import Foundation
import Ollin
import OllinPhysics

/// Hanging chains of rigid links, each a `revolute` joint (a free hinge) between
/// capsule segments, ending in a heavy ball — pendulums that swing, tangle, and
/// settle under gravity. **Click a link or ball to grab it** (a cursor-drag mouse
/// joint) and fling the chain around; **click again to let go**. Space resets.
///
/// This is the joints showcase for `OllinPhysics`: `World.connect(_:_:.revolute)`
/// builds the chain, `World.grab` does the dragging, and every link is drawn
/// straight from its `position`/`angle`.
@main
final class Chain: Sketch {
    let world = World()

    /// The dynamic links/balls a click can grab.
    var grabbable: [Body] = []
    /// The active cursor-drag joint, if a body is currently held.
    var held: Joint?

    enum Form {
        case peg(Double)
        case ball(Double)
        case capsule(Vector2, Vector2, Double)
    }
    final class Look {
        let form: Form
        let color: Color
        init(_ form: Form, _ color: Color) { self.form = form; self.color = color }
    }

    let linkColor = Color(red: 0.45, green: 0.77, blue: 0.71)
    let ballColors = [
        Color(red: 0.95, green: 0.49, blue: 0.34),
        Color(red: 0.55, green: 0.57, blue: 0.88),
        Color(red: 0.97, green: 0.71, blue: 0.30)
    ]
    let pegColor = Color(white: 0.45)

    override func setup() {
        world.gravity = Vector2(0, 2400)
        world.bounds = bounds          // keep flung chains on-canvas
        build()
        noStroke()
    }

    func build() {
        grabbable.removeAll()
        // Three chains, each starting at a different lean so they swing on launch.
        build(anchorX: width * 0.28, lean: -0.95, ball: ballColors[0])
        build(anchorX: width * 0.50, lean:  0.55, ball: ballColors[1])
        build(anchorX: width * 0.72, lean:  1.05, ball: ballColors[2])
    }

    /// One chain: a static peg, then `links` capsule segments hinged end-to-end by
    /// revolute joints, finished with a heavy ball. `lean` offsets the initial
    /// direction from straight down (radians) so it starts mid-swing.
    func build(anchorX: Double, lean: Double, ball: Color) {
        let top = Vector2(anchorX, 90 * scale)
        let seg = 50 * scale
        let dir = Vector2(angle: .pi / 2 + lean, length: seg)   // π/2 is straight down
        let unit = dir.normalized
        let links = 7

        let peg = world.addBody(.circle(radius: 10 * scale), at: top, kind: .static)
        peg.userData = Look(.peg(10 * scale), pegColor)

        var previous = peg
        for i in 1 ... links {
            let center = top + dir * Double(i)
            let pivot = top + dir * (Double(i) - 0.5)   // the hinge between segments
            let isBall = i == links

            let body: Body
            if isBall {
                body = world.addBody(.circle(radius: 30 * scale), at: center,
                                     density: 6, friction: 0.5)
                body.userData = Look(.ball(30 * scale), ball)
            } else {
                let half = unit * (seg * 0.42)
                body = world.addBody(.capsule(from: -half, to: half, radius: 11 * scale),
                                     at: center, density: 1, friction: 0.5)
                body.userData = Look(.capsule(-half, half, 11 * scale), linkColor)
            }
            world.connect(previous, body, .revolute(at: pivot))
            grabbable.append(body)
            previous = body
        }
    }

    override func mousePressed() {
        if let held {                       // already holding → let go
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

        held?.target = mouse   // drag the held body to the cursor
        world.advance(by: deltaTime)

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
                }
            }
        }
    }
}
