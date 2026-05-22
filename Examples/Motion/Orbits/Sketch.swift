import Foundation
import Ollin

/// Ten circles orbiting the center, each on a wider ring and at a faster
/// angular speed, traced with `cos`/`sin`. `map` turns the ring index into a
/// speed multiplier — 1 at the innermost ring rising toward ~8 at the
/// outermost — so the rings drift in and out of alignment over time.
///
/// The center reads live as `width / 2, height / 2`.
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
            let angle = time * map(fi, 0, 10, 1, 10)
            let x = width / 2 + orbitRadius * cos(angle)
            let y = height / 2 + orbitRadius * sin(angle)
            circle(x: x, y: y, radius: 20)
        }
    }
}
