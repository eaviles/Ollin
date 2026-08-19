// figure: frame=700
//
// Guide figure (Chapter 12): three wanderers roam, each on its own seed,
// leaving a trail. Wander is seek pointed at a jittered spot on a circle
// projected ahead, so the path curves instead of jittering in place.
import Ollin

final class Wanderer: Sketch {
    var creatures: [Vehicle] = []
    var trails: [[Vector2]] = []
    let colors = [Color(hex: 0x6FD3C7), Color(hex: 0xF2B705), Color(hex: 0xF2836B)]

    override func setup() {
        creatures = (0 ..< 3).map { i in
            Vehicle(at: Vector2(540, 340 + Double(i) * 200),
                    velocity: Vector2(angle: Double(i) * 2.1, length: 2),
                    maxSpeed: 4, maxForce: 0.15, seed: UInt64(i * 3 + 2))
        }
        trails = creatures.map { _ in [] }
    }

    override func draw() {
        for (i, creature) in creatures.enumerated() {
            creature.applyForce(creature.wander(radius: 30, distance: 90, jitter: 0.25))
            creature.applyForce(creature.contain(in: bounds, margin: 140) * 1.5)
            creature.step()
            trails[i].append(creature.position)
            if trails[i].count > 700 { trails[i].removeFirst() }
        }

        background(Color(hex: 0x101318))
        noFill()
        strokeWeight(2.5)
        for (i, trail) in trails.enumerated() where trail.count > 1 {
            stroke(colors[i].withAlpha(0.5))
            drawPolyline(trail)
        }
        noStroke()
        for (i, creature) in creatures.enumerated() {
            fill(colors[i])
            drawVehicle(creature, size: 14)
        }
    }
}
