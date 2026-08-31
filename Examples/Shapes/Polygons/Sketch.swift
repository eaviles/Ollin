//  An original Ollin sketch.

import Ollin

/// Regular polygons and stars on the analytic SDF path: the `drawNgon` and
/// `drawStar` family. The top row steps `drawNgon` from a triangle up to an
/// octagon; from the pentagon on, each cell is drawn through its named sugar
/// call instead (`drawPentagon`, `drawHexagon`, `drawHeptagon`,
/// `drawOctagon`, labeled under the shape). The named helpers are sugar over
/// `drawNgon` with the side count fixed, so they draw the same analytic SDF
/// shape; the name just saves you the `sides:` argument. The bottom row holds
/// a five-point `drawStar` whose inner radius grows left to right, so the
/// points relax from spiky to round. Everything turns with `time`, and the
/// edges stay crisp at any angle because each shape is a single
/// signed-distance instance, not a tessellated outline.
@main
final class Polygons: Sketch {
    private let palette = CosinePalette.rainbow
    private let sugarNames = ["drawPentagon", "drawHexagon", "drawHeptagon", "drawOctagon"]

    override func setup() {
        noStroke()
    }

    override func draw() {
        background(Color(white: 0.07))

        let columns = 6
        let r = shortSide * 0.085
        let topY = height * 0.36
        let bottomY = height * 0.64
        textAlign(.center)
        textSize(15 * scale)   // narrow enough that neighboring call names stay apart

        for i in 0..<columns {
            let t = Double(i) / Double(columns - 1)
            let x = map(Double(i), 0, Double(columns - 1), width * 0.14, width * 0.86)

            // Top row: regular polygons, 3..8 sides, turning one way. The
            // triangle and square go through `drawNgon`; the rest use the
            // named helpers, so both spellings have a call site.
            fill(palette.color(at: t * 0.5))
            withState {
                translate(x, topY)
                rotate(time * 0.5)
                switch i {
                case 0, 1: drawNgon(0, 0, r, sides: i + 3)
                case 2:    drawPentagon(0, 0, r)
                case 3:    drawHexagon(0, 0, r)
                case 4:    drawHeptagon(0, 0, r)
                default:   drawOctagon(0, 0, r)
                }
            }
            if i >= 2 {
                fill(.white)
                drawText(sugarNames[i - 2], x, topY + r + 50 * scale)
            }

            // Bottom row: five-point stars, inner radius growing left -> right
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
