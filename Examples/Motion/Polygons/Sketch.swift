//  An original Ollin sketch.

import Ollin

/// Regular polygons and stars on the analytic SDF path — the `drawNgon` and
/// `drawStar` family. The top row steps `drawNgon` from a triangle up to an
/// octagon; the bottom row holds a five-point `drawStar` whose inner radius grows
/// left to right, so the points relax from spiky to round. Everything turns with
/// `time`, and the edges stay crisp at any angle because each shape is a single
/// signed-distance instance, not a tessellated outline.
@main
final class Polygons: Sketch {
    private let palette = CosinePalette.rainbow

    override func setup() {
        noStroke()
    }

    override func draw() {
        background(Color(white: 0.07))

        let columns = 6
        let r = shortSide * 0.085
        let topY = height * 0.36
        let bottomY = height * 0.64

        for i in 0..<columns {
            let t = Double(i) / Double(columns - 1)
            let x = map(Double(i), 0, Double(columns - 1), width * 0.14, width * 0.86)

            // Top row: regular polygons, 3..8 sides, turning one way.
            fill(palette.color(at: t * 0.5))
            withState {
                translate(x, topY)
                rotate(time * 0.5)
                drawNgon(0, 0, r, sides: i + 3)
            }

            // Bottom row: six-point stars, inner radius growing left -> right
            // (spiky to round), turning the other way.
            fill(palette.color(at: 0.5 + t * 0.5))
            let inner = map(t, 0, 1, r * 0.32, r * 0.94)
            withState {
                translate(x, bottomY)
                rotate(-time * 0.5)
                drawStar(0, 0, r, inner, points: 5)
            }
        }
    }
}
