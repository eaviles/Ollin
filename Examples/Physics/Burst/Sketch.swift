import Foundation
import Ollin
import OllinPhysics

/// Fruit thrown up through the frame, bursting at the top of its arc into
/// pieces that tumble back down. Nobody cuts them: each one comes apart on its
/// own, and what falls is exactly what went up, in `Shape.fractured` pieces
/// that fit back together with no gap and no overlap.
///
/// The whole of the break is one call. A fruit's outline is a `Shape`, and
/// `fractured(into:around:seed:)` cuts it into cells around the point where it
/// gave way, so the chips are small there and the wedges long away from it.
/// Each piece then becomes its own rigid body: put the body at the piece's
/// `centroid`, hand the solver the piece's points around that centroid, and
/// give it the parent's motion plus a push outward from the break.
///
/// **Click** to burst the nearest fruit early. **Space** clears the frame.
@main
final class Burst: Sketch {
    let world = World()

    /// What a body draws as, hung off `Body.userData`: its outline in its own
    /// coordinates, its color, and (for a whole fruit) the upward speed at
    /// which it lets go. A piece carries no such speed and never breaks again.
    final class Look {
        let shape: Shape
        let color: Color
        let breaksAt: Double?
        init(shape: Shape, color: Color, breaksAt: Double? = nil) {
            self.shape = shape
            self.color = color
            self.breaksAt = breaksAt
        }
    }

    /// A ring at a break, drawn for a moment after it happens.
    struct Flash {
        var center: Vector2
        var color: Color
        var age = 0.0
    }
    var flashes: [Flash] = []

    let palette: [Color] = [
        Color(hex: 0xE8503A), Color(hex: 0xF2A13B), Color(hex: 0xF7D257),
        Color(hex: 0x76C36B), Color(hex: 0x4FB3C4), Color(hex: 0xB06BD1),
    ]

    override func setup() {
        world.gravity = Vector2(0, 2200 * scale)
        world.restitution = 0.2
        noStroke()
    }

    /// Throw one fruit up from under the bottom edge.
    func throwOne() {
        guard world.bodies.count < 220 else { return }
        let radius = random(52, 92) * scale
        let color = randomChoice(palette)
        let fromLeft = random() < 0.5
        let x = fromLeft ? random(width * 0.12, width * 0.4) : random(width * 0.6, width * 0.88)

        // Three kinds of fruit, each a convex outline so the whole one is a
        // single collider before it comes apart.
        let outline: [Vector2]
        let collider: Collider
        switch Int(random(3)) {
        case 0:
            outline = (0 ..< 40).map { i in
                let a = Double(i) / 40 * .tau
                return Vector2(cos(a), sin(a)) * radius
            }
            collider = .circle(radius: radius)
        case 1:
            let w = radius * 1.7, h = radius * 1.35
            outline = [Vector2(-w / 2, -h / 2), Vector2(w / 2, -h / 2),
                       Vector2(w / 2, h / 2), Vector2(-w / 2, h / 2)]
            collider = .box(width: w, height: h)
        default:
            let sides = Int(random(5, 8))
            outline = (0 ..< sides).map { i in
                let a = Double(i) / Double(sides) * .tau
                return Vector2(cos(a), sin(a)) * radius
            }
            collider = .polygon(outline)
        }

        let fruit = world.addBody(collider, at: Vector2(x, height + radius * 1.4),
                                  density: 1, friction: 0.4, restitution: 0.2)
        fruit.velocity = Vector2(random(-220, 220) * scale, -random(1750, 2050) * scale)
        fruit.angle = random(.tau)
        fruit.angularVelocity = random(-3, 3)
        fruit.userData = Look(shape: Shape(outline), color: color,
                              breaksAt: random(-140, 140) * scale)
    }

    /// Break one fruit into pieces, each with the parent's motion and a push
    /// out of the break.
    func burst(_ fruit: Body, look: Look) {
        let turn = fruit.angle
        let here = fruit.position
        // Everything the pieces inherit is read before the fruit is destroyed:
        // a body is spent the moment it leaves the world.
        let motion = fruit.velocity
        let spin = fruit.angularVelocity
        // Where it gives way: off-center, so the cut is not the same twice.
        let impact = look.shape.centroid + Vector2(random(-1, 1), random(-1, 1))
            * (look.shape.bounds.map { min($0.width, $0.height) * 0.35 } ?? 0)
        let pieces = look.shape.fractured(into: Int(random(7, 13)), around: impact,
                                          seed: Int(random(10_000)))
        world.remove(fruit)
        flashes.append(Flash(center: here + impact.rotated(by: turn), color: look.color))

        for piece in pieces {
            let middle = piece.centroid
            let local = piece.mapPoints { $0 - middle }
            guard let corners = local.contours.first?.points, corners.count >= 3 else { continue }
            // A piece that comes to rest is still the piece that was drawn, so
            // the outline the body carries is the one the solver was handed.
            let shard = world.addBody(.polygon(corners), at: here + middle.rotated(by: turn),
                                      density: 1, friction: 0.5, restitution: 0.25)
            shard.angle = turn
            let push = (middle - impact).normalized * random(180, 420) * scale
            shard.velocity = motion + push
            shard.angularVelocity = spin + random(-7, 7)
            shard.userData = Look(shape: local,
                                  color: look.color.mixed(with: .white, random(0, 0.22)))
        }
    }

    override func mousePressed() {
        // The nearest fruit still whole, which is the one with a break speed.
        let whole = world.bodies.filter { ($0.userData as? Look)?.breaksAt != nil }
        guard let nearest = whole.min(by: {
            $0.position.distance(to: mouse) < $1.position.distance(to: mouse)
        }), let look = nearest.userData as? Look else { return }
        burst(nearest, look: look)
    }

    override func keyPressed() {
        if key == " " {
            world.removeAll()
            flashes.removeAll()
        }
    }

    override func draw() {
        background(Color(hex: 0x14161C))

        if frameCount % 16 == 0 { throwOne() }
        world.advance(by: deltaTime)

        // Past the top of the arc it lets go: the fruit is on its way down, and
        // still high enough that the break happens inside the frame.
        for body in world.bodies {
            guard let look = body.userData as? Look, let breaksAt = look.breaksAt else { continue }
            if body.velocity.y >= breaksAt && body.position.y < height * 0.72 {
                burst(body, look: look)
            }
        }

        // Anything below the frame has had its fall.
        for body in world.bodies where body.position.y > height + 260 * scale {
            world.remove(body)
        }

        for body in world.bodies {
            guard let look = body.userData as? Look else { continue }
            withState {
                translate(body.position)
                rotate(body.angle)
                fill(look.color)
                // A whole fruit wears a rind, so the flesh the break reveals is
                // a lighter color inside a darker edge.
                if look.breaksAt != nil {
                    stroke(look.color.mixed(with: .black, 0.4))
                    strokeWeight(7 * scale)
                } else {
                    noStroke()
                }
                drawShape(look.shape)
            }
        }
        noStroke()

        noFill()
        for flash in flashes {
            let t = flash.age / 0.3
            strokeWeight((1 - t) * 5 * scale)
            stroke(flash.color.withAlpha((1 - t) * 0.5))
            drawCircle(center: flash.center, radius: (30 + t * 120) * scale)
        }
        noStroke()
        for i in flashes.indices { flashes[i].age += deltaTime }
        flashes.removeAll { $0.age > 0.3 }
    }
}
