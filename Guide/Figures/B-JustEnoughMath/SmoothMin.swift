// figure: frame=0 themed
//
// Guide diagram (Appendix B): the smooth minimum along one line. Two circles
// of radius 0.35 sit at -0.6 and 0.6. The faint V shapes are each circle's
// signed distance along the line through their centers, drawn up to 0.5 so
// the labels above stay clear. The ink curve is their plain min, with a sharp
// peak where the two answers tie. The accent curve is the smooth min with
// k = 1.4, which dips a quarter of k below the tie and crosses zero there,
// so the gap between the circles fills in. Below the zero line is inside.
import Ollin
import OllinDiagram

final class SmoothMin: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    let k = 1.4
    let plot = Rectangle(x: 110, y: 70, width: 660, height: 340)
    let xRange = (-1.3, 1.3)
    let yRange = (-0.5, 0.8)

    func a(_ x: Double) -> Double { abs(x + 0.6) - 0.35 }
    func b(_ x: Double) -> Double { abs(x - 0.6) - 0.35 }

    func smoothMin(_ a: Double, _ b: Double) -> Double {
        let h = max(k - abs(a - b), 0) / k
        return min(a, b) - h * h * k / 4
    }

    func point(_ x: Double, _ y: Double) -> Vector2 {
        Vector2(plot.x + (x - xRange.0) / (xRange.1 - xRange.0) * plot.width,
                plot.y + plot.height - (y - yRange.0) / (yRange.1 - yRange.0) * plot.height)
    }

    /// The curve of `f` across the plot, left out wherever it rises past `cap`.
    func curve(cap: Double = 0.8, _ f: (Double) -> Double) -> [Vector2] {
        stride(from: xRange.0, through: xRange.1, by: 0.005)
            .filter { x in f(x) <= cap }
            .map { x in point(x, f(x)) }
    }

    override func draw() {
        background(theme.paper)

        // Inside, below zero, washed; the zero line is the edge of a shape.
        noStroke()
        fill(theme.ink(0.05))
        drawRect(corner: point(xRange.0, 0), width: plot.width, height: point(0, yRange.0).y - point(0, 0).y)
        stroke(theme.ink(0.5))
        strokeWeight(1.5)
        drawLine(point(xRange.0, 0), point(xRange.1, 0))

        stroke(theme.ink(0.25))
        strokeWeight(2)
        drawPolyline(curve(cap: 0.5, a))
        drawPolyline(curve(cap: 0.5, b))

        stroke(theme.ink)
        strokeWeight(3)
        drawPolyline(curve { x in min(a(x), b(x)) })

        stroke(theme.accent)
        strokeWeight(3)
        drawPolyline(curve { x in smoothMin(a(x), b(x)) })

        // The dip at the tie, a quarter of k.
        let tie = point(0, min(a(0), b(0)))
        let dipped = point(0, smoothMin(a(0), b(0)))
        stroke(theme.accent)
        strokeWeight(1.5)
        strokeDash([5, 4])
        drawLine(tie, dipped)
        noStrokeDash()
        stroke(theme.ink(0.5))
        strokeWeight(1)
        drawLine(point(0, 0.7), tie - Vector2(0, 8))

        noStroke()
        textSize(14)
        fill(theme.accent)
        textAlign(.left, .middle)
        drawText("k / 4", tie.x + 8, dipped.y - 20)
        textSize(15)
        fill(theme.ink)
        textAlign(.center, .bottom)
        drawText("where the two answers tie, min has a sharp peak", tie.x, point(0, 0.72).y)
        fill(theme.muted)
        textSize(14)
        textAlign(.left, .bottom)
        drawText("distance to the edge", plot.x, plot.y - 8)
        textAlign(.right, .top)
        drawText("inside", plot.x + plot.width, point(0, 0).y + 8)
        drawText("outside", plot.x + plot.width, point(0, 0).y - 26)

        legend()
        diagramCaption("the dip crosses zero, so the gap between the circles fills in", at: 470, theme: theme)
    }

    func legend() {
        let x = 640.0
        let y = plot.y + 40
        strokeWeight(3)
        stroke(theme.ink)
        drawLine(x, y, x + 34, y)
        stroke(theme.accent)
        drawLine(x, y + 26, x + 34, y + 26)
        noStroke()
        textSize(15)
        textAlign(.left, .middle)
        fill(theme.ink)
        drawText("min", x + 44, y)
        fill(theme.accent)
        drawText("smooth min, k = 1.4", x + 44, y + 26)
    }
}
