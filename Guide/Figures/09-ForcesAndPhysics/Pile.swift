// figure: frame=210
//
// Guide listing (Chapter 9): the first simulated world. Discs drop, gravity
// pulls them down, the walls catch them, and collisions keep them from
// overlapping, so they pile up like gumballs in a jar.
import Ollin
import OllinPhysics

final class Pile: Sketch {
    let world = World()

    let palette = [
        Color(hex: 0xF25C54), Color(hex: 0xF2CC8F),
        Color(hex: 0x81B29A), Color(hex: 0x8187B9),
    ]

    override func setup() {
        seed(11)
        world.bounds = bounds
        world.collisions = true
        for _ in 0 ..< 240 {
            world.addParticle(at: Vector2(random(width), random(height * 0.55)),
                              radius: random(14, 44))
        }
        noStroke()
    }

    override func draw() {
        background(Color(hex: 0x101318))
        world.step(dt: deltaTime)

        for i in world.particles.indices {
            let p = world.particles[i]
            fill(palette[i % palette.count])
            drawCircle(center: p.position, radius: p.radius)
        }
    }
}
