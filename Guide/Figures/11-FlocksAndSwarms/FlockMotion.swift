// figure: gif duration=4 fps=16 width=420
//
// Guide figure (Chapter 11): the payoff in motion, from scattered start to
// flocks. Same rules as the payoff piece, fewer boids so the file stays small.
import Ollin

final class FlockMotion: Sketch {
    var flock: Boids?

    override func draw() {
        if flock == nil {
            flock = Boids(count: 300, in: bounds, seed: 7,
                          maxSpeed: 3.6 * scale, maxForce: 0.15 * scale,
                          perceptionRadius: 60 * scale, separationRadius: 24 * scale,
                          margin: 90 * scale)
        }
        guard let flock else { return }
        flock.step()

        background(Color(hex: 0x0D1017))
        noStroke()

        let size = 10 * scale
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
    }
}
