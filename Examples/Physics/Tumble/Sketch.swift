import Foundation
import Ollin
import OllinPhysics

/// A heap of assorted rigid shapes — boxes, disks, capsules, and random convex
/// polygons — raining down and piling up against the canvas floor. It's the
/// mixed-collider showcase for `OllinPhysics`: every form is one `addBody` with a
/// different `Collider`, sharing the world's gravity and walls, drawn straight
/// from its `position`/`angle`. **Click** to dump a burst at the cursor; **space**
/// clears the pile.
@main
final class Tumble: Sketch {
    let world = World()
    let maxBodies = 150

    /// A shape's geometry (in body-local space) plus its color, hung off
    /// `Body.userData`. The same `Form` drives both the collider and the drawing,
    /// so they can't drift apart.
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

    let palette: [Color] = [
        Color(red: 0.95, green: 0.49, blue: 0.34), Color(red: 0.97, green: 0.71, blue: 0.30),
        Color(red: 0.45, green: 0.77, blue: 0.71), Color(red: 0.55, green: 0.57, blue: 0.88),
        Color(red: 0.88, green: 0.53, blue: 0.70), Color(red: 0.62, green: 0.80, blue: 0.42)
    ]

    override func setup() {
        world.gravity = Vector2(0, 2200)
        world.bounce = 0.15
        world.bounds = bounds
        noStroke()
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

    override func mousePressed() {
        for _ in 0 ..< 8 {
            spawn(at: Vector2(mouseX + random(-40, 40) * scale,
                              mouseY + random(-40, 40) * scale))
        }
    }

    override func keyPressed() {
        if key == " " { world.removeAll() }
    }

    override func draw() {
        background(Color(white: 0.11))

        // A steady drizzle from just inside the ceiling until the pile caps out.
        // (Spawning above y = 0 would trap shapes against the bounds' top wall.)
        if frameCount % 5 == 0 {
            spawn(at: Vector2(random(width * 0.2, width * 0.8), 50 * scale))
        }
        world.step(dt: deltaTime)

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
