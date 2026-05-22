import Foundation
import Ollin

/// Ten circles orbiting the center, each on a wider ring and at a faster
/// angular speed, traced with `cos`/`sin`. Ported from a p5.js sketch.
///
/// Still no new features needed — p5's `map(i, 0, 10, 1, 10)` (the per-ring
/// speed) is inlined as `1 + i / 10 * 9`. This is the second sketch to reach
/// for `map()`, so it's the obvious first helper to add to Ollin.
///
/// p5's diameter-40 circle becomes `radius: 20`; the center `400, 400` reads
/// live as `width/2, height/2`.
@main
final class Orbits: Sketch {
    override func setup() {
        noStroke()
        fill(.white)
    }

    override func draw() {
        background(.black)
        for i in 0..<10 {
            let fi = Double(i)
            let orbitRadius = 100 + fi * 20
            let angle = time * (1 + fi / 10 * 9)
            let x = width / 2 + orbitRadius * cos(angle)
            let y = height / 2 + orbitRadius * sin(angle)
            circle(x: x, y: y, radius: 20)
        }
    }
}
