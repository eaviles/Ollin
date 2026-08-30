import Foundation
import Ollin
import OllinPhysics

/// A pyramid of rigid boxes that stack, lean, and topple — the rigid-body
/// showcase the Verlet particle world can't do (orientation and resting contact).
/// The stack settles under gravity against the canvas floor; **click to fire a
/// heavy ball** across the canvas from the side nearest the cursor and knock it
/// down. Press space to rebuild.
///
/// Each body is drawn straight from its `position` and `angle` — the rotation is
/// real rigid-body physics, not a fake spin — with its look hung off `userData`,
/// the same pattern the `Packing` particle example uses.
@main
final class Stack: Sketch {
    let world = World()

    /// What a body looks like, hung off `Body.userData`.
    final class Look {
        enum Form { case box(w: Double, h: Double); case ball(r: Double) }
        let form: Form
        let color: Color
        init(form: Form, color: Color) { self.form = form; self.color = color }
    }

    let bricks: [Color] = [
        Color(red: 0.91, green: 0.45, blue: 0.32),
        Color(red: 0.95, green: 0.62, blue: 0.30),
        Color(red: 0.40, green: 0.74, blue: 0.70),
        Color(red: 0.55, green: 0.56, blue: 0.86),
        Color(red: 0.86, green: 0.52, blue: 0.66)
    ]

    override func setup() {
        world.gravity = Vector2(0, 2600)   // points/s² — a firm, visible pull
        world.restitution = 0.05                // a low-restitution floor so it settles
        world.bounds = bounds
        buildStack()
        noStroke()
    }

    /// A centered pyramid: each row one brick narrower, offset half a brick so every
    /// upper box straddles the seam of the two below — a classic stable stack that
    /// stands cleanly and topples convincingly when struck.
    func buildStack() {
        let bw = 120 * scale, bh = 52 * scale
        let pitch = bw + 3 * scale         // a hair of gap so resting boxes don't fight
        let rows = 7

        for row in 0 ..< rows {
            let count = rows - row
            let y = height - 8 * scale - (Double(row) + 0.5) * bh
            let rowWidth = Double(count) * pitch
            let startX = (width - rowWidth) / 2 + pitch / 2
            for c in 0 ..< count {
                let x = startX + Double(c) * pitch
                let body = world.addBody(.box(width: bw, height: bh), at: Vector2(x, y),
                                         friction: 0.7, restitution: 0.02)
                body.userData = Look(form: .box(w: bw, h: bh), color: bricks[row % bricks.count])
            }
        }
    }

    /// Fire a dense ball in from the side nearest the cursor, aimed across at the
    /// cursor's height.
    override func mousePressed() {
        let r = 30 * scale
        let fromLeft = mouseX < width / 2
        let startX = fromLeft ? r : width - r
        let ball = world.addBody(.circle(radius: r), at: Vector2(startX, mouseY),
                                 density: 5, friction: 0.4, restitution: 0.2)
        ball.velocity = Vector2((fromLeft ? 1 : -1) * 2600 * scale, -150 * scale)
        ball.userData = Look(form: .ball(r: r), color: Color(white: 0.95))
    }

    override func keyPressed() {
        if key == " " {
            world.removeAll()
            buildStack()
        }
    }

    override func draw() {
        background(Color(white: 0.12))
        world.advance(by: deltaTime)

        for body in world.bodies {
            guard let look = body.userData as? Look else { continue }
            withState {
                translate(body.position)
                rotate(body.angle)
                fill(look.color)
                switch look.form {
                case .box(let w, let h):
                    drawRect(center: .zero, width: w, height: h, cornerRadius: 3 * scale)
                case .ball(let r):
                    drawCircle(center: .zero, radius: r)
                }
            }
        }
    }
}
