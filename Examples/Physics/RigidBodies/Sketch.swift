import Foundation
import Ollin
import OllinPhysics

/// The rigid-body showcase in one scene. On the right, a pyramid of crates that
/// stacks, leans, and topples: orientation and resting contact, the things the
/// Verlet particle world can't do. On the left, a rain of assorted shapes
/// (boxes, disks, capsules, and random convex polygons) piling up against the
/// floor: every form is one `addBody` with a different `Collider`, all sharing
/// one world's gravity and walls. **Click to fire a heavy ball** across the
/// canvas from the side nearest the cursor and knock the pyramid into the
/// heap, or plow the heap into the pyramid. Press space to clear the pile and
/// rebuild the stack.
///
/// Each body is drawn straight from its `position` and `angle` (the rotation is
/// real rigid-body physics, not a fake spin). The same `Form` value drives both
/// the collider and the drawing, so they can't drift apart, and it is hung off
/// `Body.userData` along with the color, the same pattern the `Packing`
/// particle example uses.
@main
final class RigidBodies: Sketch {
    let world = World()
    let maxBodies = 150

    /// A shape's geometry (in body-local space) plus its color, hung off
    /// `Body.userData`.
    enum Form {
        case box(w: Double, h: Double)
        case ball(r: Double)
        case capsule(from: Vector2, to: Vector2, r: Double)
        case polygon([Vector2])
    }
    final class Look {
        let form: Form
        let color: Color
        init(_ form: Form, _ color: Color) { self.form = form; self.color = color }
    }

    /// One color per pyramid row.
    let bricks: [Color] = [
        Color(red: 0.91, green: 0.45, blue: 0.32),
        Color(red: 0.95, green: 0.62, blue: 0.30),
        Color(red: 0.40, green: 0.74, blue: 0.70),
        Color(red: 0.55, green: 0.56, blue: 0.86),
        Color(red: 0.86, green: 0.52, blue: 0.66)
    ]

    /// Random picks for the raining shapes.
    let palette: [Color] = [
        Color(red: 0.95, green: 0.49, blue: 0.34), Color(red: 0.97, green: 0.71, blue: 0.30),
        Color(red: 0.45, green: 0.77, blue: 0.71), Color(red: 0.55, green: 0.57, blue: 0.88),
        Color(red: 0.88, green: 0.53, blue: 0.70), Color(red: 0.62, green: 0.80, blue: 0.42)
    ]

    override func setup() {
        world.gravity = Vector2(0, 2600)   // points/s², a firm, visible pull
        world.restitution = 0.05           // a low-restitution floor so the stack settles
        world.bounds = bounds
        buildStack()
        noStroke()
    }

    /// A pyramid on the right: each row one crate narrower, offset half a crate
    /// so every upper box straddles the seam of the two below, a classic stable
    /// stack that stands cleanly and topples convincingly when struck.
    func buildStack() {
        let bw = 96 * scale, bh = 44 * scale
        let pitch = bw + 3 * scale         // a hair of gap so resting boxes don't fight
        let rows = 6
        let middle = width * 0.68

        for row in 0 ..< rows {
            let count = rows - row
            let y = height - 8 * scale - (Double(row) + 0.5) * bh
            let rowWidth = Double(count) * pitch
            let startX = middle - rowWidth / 2 + pitch / 2
            for c in 0 ..< count {
                let x = startX + Double(c) * pitch
                let body = world.addBody(.box(width: bw, height: bh), at: Vector2(x, y),
                                         friction: 0.7, restitution: 0.02)
                body.userData = Look(.box(w: bw, h: bh), bricks[row % bricks.count])
            }
        }
    }

    /// A random convex form, sized in canvas points.
    func randomForm() -> Form {
        let s = random(26, 52) * scale
        switch Int(random(4)) {
        case 0:  return .box(w: s * 2, h: random(0.6, 1.0) * s * 1.7)
        case 1:  return .ball(r: s)
        case 2:  return .capsule(from: Vector2(-s, 0), to: Vector2(s, 0), r: s * 0.55)
        default:
            let sides = Int(random(3, 6.99))
            let points = (0 ..< sides).map { i -> Vector2 in
                let angle = Double(i) / Double(sides) * .tau + random(-0.18, 0.18)
                return Vector2(angle: angle, length: s * random(0.82, 1.15))
            }
            return .polygon(points)
        }
    }

    func collider(for form: Form) -> Collider {
        switch form {
        case .box(let w, let h):        return .box(width: w, height: h)
        case .ball(let r):              return .circle(radius: r)
        case .capsule(let a, let b, let r): return .capsule(from: a, to: b, radius: r)
        case .polygon(let points):      return .polygon(points)
        }
    }

    /// Drop one random shape at `position` with a little spin.
    func spawn(at position: Vector2) {
        guard world.bodies.count < maxBodies else { return }
        let form = randomForm()
        let body = world.addBody(collider(for: form), at: position,
                                 density: 1, friction: 0.5,
                                 restitution: random(0.05, 0.35))
        body.angle = random(.tau)
        body.angularVelocity = random(-4, 4)
        body.userData = Look(form, palette[Int(random(Double(palette.count)))])
    }

    /// Fire a dense ball in from the side nearest the cursor, aimed across at
    /// the cursor's height.
    override func mousePressed() {
        let r = 30 * scale
        let fromLeft = mouseX < width / 2
        let startX = fromLeft ? r : width - r
        let ball = world.addBody(.circle(radius: r), at: Vector2(startX, mouseY),
                                 density: 5, friction: 0.4, restitution: 0.2)
        ball.velocity = Vector2((fromLeft ? 1 : -1) * 2600 * scale, -150 * scale)
        ball.userData = Look(.ball(r: r), Color(white: 0.95))
    }

    override func keyPressed() {
        if key == " " {
            world.removeAll()
            buildStack()
        }
    }

    override func draw() {
        background(Color(white: 0.12))

        // A steady drizzle over the left side from just inside the ceiling
        // until the pile caps out. (Spawning above y = 0 would trap shapes
        // against the bounds' top wall.)
        if frameCount % 5 == 0 {
            spawn(at: Vector2(random(width * 0.06, width * 0.38), 50 * scale))
        }
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
                case .capsule(let a, let b, let r):
                    stroke(look.color)
                    strokeWeight(2 * r)
                    drawLine(a, b)
                case .polygon(let points):
                    drawPolygon(points)
                }
            }
        }
    }
}
