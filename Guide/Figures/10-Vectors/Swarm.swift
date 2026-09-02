// figure: frame=130
//
// Guide payoff (Chapter 10): a swarm chasing a lure. Every mover keeps a
// position and a velocity, steers toward the lure (aim, compare, correct),
// and draws itself as a streak along its own velocity. The lure wanders on
// noise until the mouse is held down, which takes it over.
import Ollin

final class Swarm: Sketch {
    @Param("Movers", 40...400) var movers = 260
    @Param("Speed", 150...800) var maxSpeed = 430.0
    @Param("Chase", 300...3000) var maxForce = 950.0

    var positions: [Vector2] = []
    var velocities: [Vector2] = []
    var quickness: [Double] = []      // a personality per mover

    let ramp = Ramp([
        Color(hex: 0x274690), Color(hex: 0x2A9D8F),
        Color(hex: 0xE9C46A), Color(hex: 0xF25C54),
    ])

    override func setup() {
        seed(9)
        strokeCap(.round)
    }

    override func draw() {
        background(Color(hex: 0x0C0F14))

        // Keep the population matched to the parameter.
        while positions.count < movers {
            positions.append(Vector2(random(width), random(height)))
            velocities.append(Vector2(angle: random(0, .tau), length: 60))
            quickness.append(random(0.55, 1.2))
        }
        if positions.count > movers {
            positions.removeLast(positions.count - movers)
            velocities.removeLast(velocities.count - movers)
            quickness.removeLast(quickness.count - movers)
        }

        // The lure wanders on noise; hold the mouse to take it over.
        var lure = Vector2(noise(time * 0.3, 3) * width,
                           noise(time * 0.3, 77) * height)
        if mouseIsPressed { lure = Vector2(mouseX, mouseY) }

        for i in positions.indices {
            // Steer: aim at the lure, compare with the current velocity,
            // and correct by a bounded amount.
            let top = maxSpeed * quickness[i]
            let desired = (lure - positions[i]).normalized * top
            let steer = (desired - velocities[i]).limited(to: maxForce)
            velocities[i] = (velocities[i] + steer * deltaTime).limited(to: top)
            positions[i] += velocities[i] * deltaTime

            // Wrap: leave one edge, come back on the other.
            var p = positions[i]
            if p.x < -20 { p = p.with(x: width + 20) }
            if p.x > width + 20 { p = p.with(x: -20) }
            if p.y < -20 { p = p.with(y: height + 20) }
            if p.y > height + 20 { p = p.with(y: -20) }
            positions[i] = p

            // A streak along the velocity, colored by personality:
            // the quick ones warm, the slow ones cool.
            let pace = map(quickness[i], 0.55, 1.2, 0, 1)
            stroke(ramp.color(at: pace))
            strokeWeight(1.5 + pace * 2.8)
            drawLine(positions[i] - velocities[i] * 0.11, positions[i])
        }

        noStroke()
        fill(Color(white: 1, alpha: 0.55))
        drawCircle(center: lure, radius: 5)
    }
}
