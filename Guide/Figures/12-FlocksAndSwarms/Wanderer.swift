// figure: frame=700
//
// Guide figure (Chapter 12): three wanderers roam, each on its own seed,
// leaving a trail. Wander is seek pointed at a jittered spot on a circle
// projected ahead, so the path curves instead of jittering in place. The
// trails come from fading the canvas a little each frame instead of
// clearing it, the same trick the chapter's finished flock uses.
import Ollin

final class Wanderer: Sketch {
    var creatures: [Vehicle] = []
    let colors = [Color(hex: 0x6FD3C7), Color(hex: 0xF2B705), Color(hex: 0xF2836B)]

    override func setup() {
        creatures = (0 ..< 3).map { i in
            Vehicle(at: Vector2(540, 340 + Double(i) * 200),
                    velocity: Vector2(angle: Double(i) * 2.1, length: 2),
                    maxSpeed: 4, maxForce: 0.15, seed: i * 3 + 2)
        }
        background(Color(hex: 0x101318))
        noClear()
    }

    override func draw() {
        for creature in creatures {
            creature.applyForce(creature.wander(radius: 30, distance: 90, jitter: 0.25))
            creature.applyForce(creature.contain(in: bounds, margin: 140) * 1.5)
            creature.step()
        }

        // Fade the last frame a little instead of erasing it: trails.
        noStroke()
        fill(Color(hex: 0x101318).withAlpha(0.01))
        drawRect(bounds)

        for (i, creature) in creatures.enumerated() {
            fill(colors[i])
            drawVehicle(creature, size: 14)
        }
    }
}
