// figure: frame=58
//
// Guide listing (Chapter 11): a shape thrown up that breaks at the top of its
// arc into pieces that fall on their own, each piece a rigid body of its own.
import Ollin
import OllinPhysics

final class Break: Sketch {
    let world = World()

    /// What a body draws as: its outline in its own coordinates and its color.
    /// A whole shape is the only kind that breaks.
    final class Look {
        let shape: Shape
        let color: Color
        let whole: Bool
        init(_ shape: Shape, _ color: Color, whole: Bool = false) {
            self.shape = shape
            self.color = color
            self.whole = whole
        }
    }

    override func setup() {
        seed(4)
        world.gravity = Vector2(0, 2200)
        noStroke()

        let outline = (0 ..< 40).map { i -> Vector2 in
            let a = Double(i) / 40 * .tau
            return Vector2(cos(a), sin(a)) * 170
        }
        let thrown = world.addBody(.circle(radius: 170), at: Vector2(width / 2, height + 220))
        thrown.velocity = Vector2(0, -1750)
        thrown.userData = Look(Shape(outline), Color(hex: 0xF2A93B), whole: true)
    }

    /// Break one body into pieces, each piece a body of its own.
    func burst(_ body: Body, _ look: Look) {
        let here = body.position
        let motion = body.velocity
        let impact = Vector2(random(-60, 60), random(-60, 60))
        let pieces = look.shape.fractured(into: 11, around: impact, seed: 4)
        world.remove(body)

        for piece in pieces {
            let middle = piece.centroid
            let local = piece.mapPoints { $0 - middle }
            guard let corners = local.contours.first?.points else { continue }
            let shard = world.addBody(.polygon(corners), at: here + middle)
            shard.velocity = motion + (middle - impact).normalized * 300
            shard.angularVelocity = random(-6, 6)
            shard.userData = Look(local, look.color.mixed(with: .white, random(0, 0.2)))
        }
    }

    override func draw() {
        background(Color(hex: 0x14161C))
        world.advance(by: deltaTime)

        // At the top of the arc it is on its way down, and that is when it goes.
        for body in world.bodies {
            guard let look = body.userData as? Look, look.whole else { continue }
            if body.velocity.y >= 0 { burst(body, look) }
        }

        for body in world.bodies {
            guard let look = body.userData as? Look else { continue }
            withState {
                translate(body.position)
                rotate(body.angle)
                fill(look.color)
                drawShape(look.shape)
            }
        }
    }
}
