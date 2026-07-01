import Ollin

/// Flocking: a few hundred boids, each steering only by what its neighbors do,
/// yet the flock as a whole swirls, splits, and regroups with no leader. Every
/// boid follows three local rules, steer away from crowding, match the heading of
/// nearby boids, and drift toward their center, and the coherent motion emerges.
///
/// The boids are drawn as little triangles pointing along their velocity and
/// tinted by heading, so boids travelling the same way share a color and each
/// sub-flock reads as its own band. It's pure simulation, so it never settles.
@main
final class Flocking: Sketch {
    private var flock: Boids?

    override func draw() {
        if flock == nil {
            flock = Boids(count: 520, in: bounds, seed: 7,
                          maxSpeed: 3.4 * scale, maxForce: 0.14 * scale,
                          perceptionRadius: 56 * scale, separationRadius: 26 * scale,
                          margin: 80 * scale)
        }
        guard let flock else { return }
        flock.step()

        background(Color(hex: 0x0E1016))
        noStroke()

        let size = 9 * scale
        for i in 0 ..< flock.count {
            let p = flock.positions[i]
            let a = flock.heading(i)
            fill(Color(hue: (a + .pi) / (2 * .pi), saturation: 0.55, brightness: 0.96))
            let nose = Vector2(p.x + cos(a) * size, p.y + sin(a) * size)
            let left = Vector2(p.x + cos(a + 2.5) * size * 0.7, p.y + sin(a + 2.5) * size * 0.7)
            let right = Vector2(p.x + cos(a - 2.5) * size * 0.7, p.y + sin(a - 2.5) * size * 0.7)
            drawTriangle(nose, left, right)
        }
    }
}
