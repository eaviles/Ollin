//  Scene composition after @eaviles's sketch 2025.037 (a packed field of
//  spinning crosshair tokens). The physics here is Ollin's own — an
//  `OllinPhysics` Verlet world with disk collisions — not a port of that
//  sketch's collision math.

import Foundation
import Ollin
import OllinPhysics

/// A field of discs drifting weightlessly, bouncing off the walls and off each
/// other, each drawn as a slowly spinning token: a translucent disk, a crosshair,
/// a crisp rim, and a centre dot. The packing and the bouncing are the physics;
/// the spin reacts to each token's own speed, so a collision that speeds a token
/// up spins it faster.
///
/// This is the headline for `OllinPhysics.World` collisions: 256 disks resolved
/// pairwise every frame with `world.collisions = true`, no gravity, walls at the
/// canvas edge.
@main
final class Packing: Sketch {
    let world = World()
    let count = 256

    /// Per-token spin state, hung off each particle via `userData`.
    final class Token {
        var rotation: Double
        let spin: Double          // sign + base rate
        init(rotation: Double, spin: Double) {
            self.rotation = rotation
            self.spin = spin
        }
    }

    override func setup() {
        world.gravity = .zero              // weightless drift
        world.drag = 0                     // no damping — the field drifts forever
        world.bounce = 1.0                 // walls lose no speed
        world.collisions = true
        world.iterations = 3               // a packing needs few passes to settle
        world.bounds = bounds

        noStroke()

        for _ in 0 ..< count {
            let radius = random(8, 32) * scale
            // Find a spot that isn't already taken (reject overlaps).
            guard let position = freeSpot(radius: radius) else { continue }

            // Heavier discs (more area) shove lighter ones around.
            let particle = world.addParticle(at: position, radius: radius,
                                             mass: (radius / scale) * (radius / scale))
            // Launch it in a random direction; `push` is a per-step displacement.
            particle.push(Vector2(angle: random(.tau), length: random(0.8, 2.8) * scale))
            particle.userData = Token(rotation: random(.tau),
                                      spin: (random() < 0.5 ? -1 : 1) * random(0.5, 1.5))
        }
    }

    /// A position whose disk doesn't overlap any placed one, or `nil` after a
    /// budget of tries (so a crowded field just places fewer).
    func freeSpot(radius: Double) -> Vector2? {
        for _ in 0 ..< 200 {
            let candidate = Vector2(random(radius, width - radius),
                                    random(radius, height - radius))
            let clear = world.particles.allSatisfy {
                candidate.distance(to: $0.position) > radius + $0.radius
            }
            if clear { return candidate }
        }
        return nil
    }

    override func draw() {
        background(.black)
        world.step(dt: deltaTime)

        let weight = 2 * scale
        for particle in world.particles {
            guard let token = particle.userData as? Token else { continue }
            // Spin faster the faster the token is moving.
            token.rotation += token.spin * (0.01 + particle.velocity.length * 0.012)
            drawToken(particle, token: token, weight: weight)
        }
    }

    func drawToken(_ particle: Particle, token: Token, weight: Double) {
        let r = particle.radius
        withState {
            translate(particle.position)

            // Translucent body.
            noStroke()
            fill(Color(white: 1, alpha: 0.33))
            drawCircle(center: .zero, radius: r)

            // Rotating crosshair.
            rotate(token.rotation)
            stroke(Color(white: 1, alpha: 0.67))
            strokeWeight(weight)
            drawLine(-r, 0, r, 0)
            drawLine(0, -r, 0, r)

            // Crisp rim and centre dot.
            noFill()
            stroke(.white)
            drawCircle(center: .zero, radius: r - 1)
            noStroke()
            fill(.white)
            drawCircle(center: .zero, radius: 4 * scale)
        }
    }
}
