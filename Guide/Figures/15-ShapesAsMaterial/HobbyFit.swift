// figure: frame=0 themed
//
// Guide diagram (Chapter 15): one row of unevenly spaced dots threaded three
// ways. Straight segments, the neighbor-by-neighbor spline drawCurve uses by
// default, and Hobby's fit, which looks at the whole run and bends evenly
// through every dot.
import Ollin
import OllinDiagram

final class HobbyFit: Sketch {
    override var canvasSize: CanvasSize { .size(880, 340) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }

    override func draw() {
        background(paper)
        textSize(17)

        let titles = ["drawPolyline", "drawCurve", "drawCurve(spline: .hobby)"]

        for i in 0 ..< 3 {
            let r = Rectangle(x: 68 + Double(i) * 260, y: 56, width: 230, height: 196)
            noFill()
            stroke(soft)
            strokeWeight(2)
            drawRect(r)

            let dots = points(in: r)
            withState {
                stroke(ink)
                strokeWeight(5)
                strokeCap(.round)
                switch i {
                case 0: drawPolyline(dots)
                case 1: drawCurve(dots)
                default: drawCurve(dots, spline: .hobby)
                }
            }

            noStroke()
            fill(theme.accent(1))
            for p in dots { drawCircle(center: p, radius: 6) }

            fill(ink)
            textAlign(.center, .top)
            drawText(titles[i], r.center.x, r.y + r.height + 14)
        }
    }

    /// Six dots placed by hand, two of them close together and one far off,
    /// the spacing that tells the two splines apart.
    private func points(in r: Rectangle) -> [Vector2] {
        [Vector2(0.06, 0.62), Vector2(0.20, 0.30), Vector2(0.30, 0.26),
         Vector2(0.62, 0.78), Vector2(0.80, 0.34), Vector2(0.94, 0.52)].map {
            Vector2(r.x + $0.x * r.width, r.y + $0.y * r.height)
        }
    }
}
