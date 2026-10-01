// figure: frame=480
//
// Guide payoff (Chapter 12): a living flock, colored by heading, with one
// predator on its tail. Every boid follows the same three local rules over its
// neighbors, no leader anywhere, and the bands of color are sub-flocks that
// have agreed on a direction. The predator is a Vehicle pursuing the first
// boid; the flock never sees it. Trails come from fading the canvas instead of
// clearing it.
import Ollin

final class Flock: Sketch {
    @Param("Separation", 0...3) var separation = 1.6
    @Param("Alignment", 0...3) var alignment = 1.1
    @Param("Cohesion", 0...3) var cohesion = 0.9

    var flock: Boids?
    var predator: Vehicle?

    override func setup() {
        background(Color(hex: 0x0D1017))
        noClear()
        flock = Boids(count: 520, in: bounds, seed: 7,
                      maxSpeed: 3.6 * scale, maxForce: 0.15 * scale,
                      perceptionRadius: 60 * scale, separationRadius: 24 * scale,
                      margin: 90 * scale)
        predator = Vehicle(at: bounds.center,
                           maxSpeed: 3.2 * scale, maxForce: 0.1 * scale)
    }

    override func draw() {
        guard let flock, let predator else { return }
        flock.separation = separation
        flock.alignment = alignment
        flock.cohesion = cohesion
        flock.step()

        // The predator hunts the first boid, aiming where it will be.
        predator.applyForce(predator.pursue(flock.positions[0],
                                            velocity: flock.velocities[0]))
        predator.step()

        // Fade the last frame a little instead of erasing it: trails.
        noStroke()
        fill(Color(hex: 0x0D1017).withAlpha(0.16))
        drawRect(bounds)

        let size = 9 * scale
        for i in 0 ..< flock.count {
            let heading = flock.heading(i)
            fill(Color(hue: (heading + .pi) / .tau + 0.55,
                       saturation: 0.58, brightness: 0.97))
            withState {
                translate(flock.positions[i])
                rotate(heading)
                drawTriangle(Vector2(size, 0),
                             Vector2(-size * 0.65, size * 0.5),
                             Vector2(-size * 0.65, -size * 0.5))
            }
        }

        fill(Color(hex: 0xF2EEE4).withAlpha(0.9))
        drawVehicle(predator, size: 40 * scale)
    }
}
