// figure: frame=0 themed
//
// Guide diagram (Appendix B): a number field's slope. The thin lines are the
// field's contours, places at one height. Each accent arrow is the gradient
// at a point of a grid, measured by central differences: it points uphill,
// its length is how steep the climb is, and it crosses the contour there at a
// right angle, so the contour runs along the arrow's perpendicular.
import Ollin
import OllinDiagram

final class Slope: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    /// A smooth hill-and-hollow field: three bumps up, one down.
    func height(_ p: Vector2) -> Double {
        func bump(_ c: Vector2, _ r: Double) -> Double { exp(-(p - c).lengthSquared / (r * r)) }
        return bump(Vector2(300, 220), 150) + 0.8 * bump(Vector2(610, 300), 120)
            - 0.6 * bump(Vector2(470, 120), 90) + 0.5 * bump(Vector2(180, 420), 110)
    }

    override func draw() {
        background(theme.paper)
        let box = Rectangle(x: 40, y: 30, width: 800, height: 440)

        // The contours.
        noFill()
        stroke(theme.ink(0.3))
        strokeWeight(1.2)
        let levels = Array(stride(from: -0.5, through: 1.2, by: 0.1))
        for group in isolines(at: levels, in: box, resolution: 120, field: height) {
            for line in group { drawPolyline(line.points, closed: line.isClosed) }
        }

        // The gradient on a grid: uphill, as long as the climb is steep.
        strokeCap(.round)
        stroke(theme.accent)
        strokeWeight(2.4)
        fill(theme.accent)
        for point in Grid(in: box.inset(by: 20), columns: 15, rows: 8).points {
            let p = point.position
            let slope = gradient(at: p, field: height)
            let length = min(slope.length * 6_000, 44)
            guard length > 9 else { continue }
            let tail = p - slope.normalized * (length / 2)
            drawArrow(from: tail, to: tail + slope.normalized * length,
                      headLength: 9, headWidth: 8)
        }

        diagramCaption("each arrow points uphill, across the contour, as long as the slope is steep",
                       at: 505, theme: theme)
    }
}
