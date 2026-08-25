// figure: frame=0 themed
//
// Guide diagram (Chapter 14): level curves. The same scalar noise field
// shown as tone, then traced at one level, then at a stack of them, which
// is how a map draws a hill.
import Ollin
import OllinDiagram

final class Isolines: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }
    var accent: Color { theme.accent }

    var tone: Image?

    override func setup() {
        noiseSeed(5)
        let size = 262
        let picture = Image(width: size, height: size)
        for y in 0 ..< size {
            for x in 0 ..< size {
                let v = height(at: Vector2(Double(x), Double(y)))
                picture[x, y] = Color(white: v)
            }
        }
        tone = picture
    }

    override func draw() {
        background(paper)
        noiseSeed(5)

        let panels = (0 ..< 3).map {
            Rectangle(x: 25 + Double($0) * 284, y: 66, width: 262, height: 262)
        }

        if let tone { drawImage(tone, in: panels[0]) }

        // One level: the shoreline of everything above 0.55.
        noFill()
        stroke(accent)
        strokeWeight(1.8)
        let originB = Vector2(panels[1].x, panels[1].y)
        for curve in isolines(at: 0.55, in: panels[1], resolution: 200,
                              field: { self.height(at: $0 - originB) }) {
            drawPolyline(curve.points, closed: curve.isClosed)
        }

        // A stack of levels, with every fifth one drawn heavy, the way a
        // cartographer marks an index contour.
        let levels = Array(stride(from: 0.3, through: 0.75, by: 0.045))
        let originC = Vector2(panels[2].x, panels[2].y)
        let groups = isolines(at: levels, in: panels[2], resolution: 200,
                              field: { self.height(at: $0 - originC) })
        for (i, group) in groups.enumerated() {
            stroke(ink)
            strokeWeight(i % 5 == 0 ? 2 : 0.8)
            for curve in group {
                drawPolyline(curve.points, closed: curve.isClosed)
            }
        }

        frame(panels[0], title: "the field, as tone")
        frame(panels[1], title: "one level")
        frame(panels[2], title: "a stack of levels")

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("a contour is just the set of points where the field agrees",
                 width / 2, 364)
    }

    /// The scalar field, in panel-local coordinates.
    func height(at p: Vector2) -> Double {
        fbm(p.x * 0.006, p.y * 0.006, octaves: 4)
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textSize(17)
        textAlign(.left, .middle)
        drawText(title, r.x, r.y - 20)
    }
}
