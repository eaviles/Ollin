//  An original Ollin sketch.

import Ollin

/// The two `drawTriangle` forms, and how each one pivots when you rotate it.
///
/// `drawTriangle(x, y, radius)` is an equilateral triangle *centered* at
/// `(x, y)` (point-up, circumradius `radius`), so rotating it spins it about
/// that center. `drawTriangle(x, y, base, height)` is an isosceles triangle
/// whose *apex* (tip) is at `(x, y)`, so rotating it sweeps the triangle about
/// the tip — the dot stays put. Both are analytic SDF shapes, so the edges stay
/// crisp at any angle. The black dot marks each pivot.
@main
final class Triangles: Sketch {
    override func draw() {
        background(.white)
        noStroke()

        let cy = height / 2
        let r = 150 * scale

        // Left — equilateral, pivoting on its center.
        fill(Color(red: 0.10, green: 0.45, blue: 0.85))
        withState {
            translate(width * 0.32, cy)
            rotate(time)
            drawTriangle(0, 0, r)
        }

        // Right — isosceles wedge, pivoting on its apex.
        fill(Color(red: 0.95, green: 0.35, blue: 0.20))
        withState {
            translate(width * 0.68, cy)
            rotate(time)
            drawTriangle(0, 0, r, r * 1.6)
        }

        // Mark each pivot so the difference reads.
        fill(.black)
        drawPoint(width * 0.32, cy, 10 * scale)
        drawPoint(width * 0.68, cy, 10 * scale)
    }
}
