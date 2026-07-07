// figure: gif duration=3.5 fps=12 width=360
//
// Guide figure (Chapter 12): particles riding the field. Every frame, each
// one takes a small step along the flow at its own position, dragging a
// short trail; swimmers that leave the canvas are reborn somewhere new.
import Ollin

final class Drift: Sketch {
    var particles: [Vector2] = []
    var trails: [[Vector2]] = []
    var respawn = SplitMix64(seed: 3)

    override func setup() {
        seed(7)
        particles = poissonDisk(radius: 88)
        trails = particles.map { [$0] }
    }

    override func draw() {
        seed(7)   // the same field every frame
        let field = curlField(scale: 0.0022)

        particles = field.advected(particles, stepLength: 7)
        for i in particles.indices {
            if !bounds.contains(particles[i]) {
                particles[i] = Vector2(Double.random(in: 0 ..< 1, using: &respawn) * width,
                                       Double.random(in: 0 ..< 1, using: &respawn) * height)
                trails[i] = []
            }
            trails[i].append(particles[i])
            if trails[i].count > 22 { trails[i].removeFirst() }
        }

        background(Color(hex: 0x101318))
        noFill()
        stroke(Color(hex: 0x9AD9CE).withAlpha(0.75))
        strokeWeight(2.6)
        strokeCap(.round)
        for trail in trails where trail.count > 1 {
            drawPolyline(trail)
        }
    }
}
