// figure: frame=0 themed
//
// Guide diagram (Appendix B): the inverse square. Left, light from a point
// spreads through a square window at distance 1, then covers a square twice
// as wide at distance 2 and three times as wide at distance 3, drawn in an
// oblique view with the four edges of the beam fanning out from the source.
// The same light covers 1, 4, then 9 cells, so each cell gets 1, 1/4, then
// 1/9 of it. Right, that share plotted against distance.
import Ollin
import OllinDiagram

final class InverseSquare: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    let source = Vector2(70, 250)
    let step = 140.0      // screen distance from one unit of distance to the next
    let unit = 38.0       // side of one cell at distance 1
    let slant = 0.42      // how far the depth axis leans in the oblique view

    /// A point in the beam: `d` along the axis, `y` up, `z` toward the viewer.
    func screen(_ d: Double, _ y: Double, _ z: Double) -> Vector2 {
        Vector2(source.x + d * step - z * slant, source.y - y + z * slant)
    }

    override func draw() {
        background(theme.paper)
        beam()
        plot(Rectangle(x: 600, y: 90, width: 240, height: 290))
        diagramCaption("the same light spreads over 1, 4, then 9 cells", at: 488, theme: theme)
    }

    func beam() {
        let far = 3.0
        let half = unit * far / 2

        // The four edges of the beam, from the source past the last window.
        stroke(theme.ink(0.3))
        strokeWeight(1.5)
        for (y, z) in [(half, half), (half, -half), (-half, half), (-half, -half)] {
            drawLine(source, screen(far, y, z))
        }

        for d in 1...3 {
            window(at: Double(d))
        }

        noStroke()
        fill(theme.accent)
        drawCircle(center: source, radius: 7)
        fill(theme.ink)
        textSize(15)
        textAlign(.center, .top)
        drawText("source", source.x, source.y + 16)
    }

    /// The square the beam fills at distance `d`, cut into d × d cells.
    func window(at d: Double) {
        let n = Int(d)
        let side = unit * d
        let half = side / 2
        let corners = [screen(d, half, -half), screen(d, half, half),
                       screen(d, -half, half), screen(d, -half, -half)]

        noStroke()
        fill(theme.accent(0.12))
        drawPolygon(corners)

        stroke(theme.ink(0.35))
        strokeWeight(1)
        for i in 1..<n {
            let s = -half + Double(i) * unit
            drawLine(screen(d, s, -half), screen(d, s, half))
            drawLine(screen(d, half, s), screen(d, -half, s))
        }
        stroke(theme.accent)
        strokeWeight(2)
        drawPolyline(corners, closed: true)

        noStroke()
        fill(theme.ink)
        textSize(15)
        textAlign(.center, .top)
        let bottom = screen(d, -half, half)
        drawText("distance \(n)", bottom.x, bottom.y + 12)
        fill(theme.muted)
        drawText(n == 1 ? "1 cell" : "\(n * n) cells", bottom.x, bottom.y + 32)
    }

    /// Brightness of one cell against distance, 1 over distance squared.
    func plot(_ r: Rectangle) {
        func point(_ d: Double, _ share: Double) -> Vector2 {
            Vector2(r.x + (d - 0.5) / 3.5 * r.width, r.y + r.height - share * r.height)
        }

        stroke(theme.ink(0.5))
        strokeWeight(1.5)
        drawLine(r.x, r.y + r.height, r.x + r.width, r.y + r.height)
        drawLine(r.x, r.y, r.x, r.y + r.height)

        stroke(theme.ink)
        strokeWeight(2.5)
        drawPolyline(stride(from: 0.8, through: 4.0, by: 0.02).map { d in
            point(d, 1 / (d * d) / 1.6)
        })

        noStroke()
        textSize(14)
        for (d, label) in [(1.0, "1"), (2.0, "1/4"), (3.0, "1/9")] {
            let p = point(d, 1 / (d * d) / 1.6)
            fill(theme.accent)
            drawCircle(center: p, radius: 5)
            fill(theme.ink)
            textAlign(.left, .bottom)
            drawText(label, p.x + 8, p.y - 4)
        }

        fill(theme.muted)
        textAlign(.center, .top)
        drawText("distance", r.x + r.width / 2, r.y + r.height + 10)
        textAlign(.left, .bottom)
        drawText("light in one cell", r.x, r.y - 10)
    }
}
