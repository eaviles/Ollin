// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Drawing.md, drawShape): the two faces of a
// Shape. A frame built from an outer square and a hole, filled even-odd, and
// a curved outline traced inline with the Path pen and filled the same way.
import Ollin
import OllinDiagram

final class DrawShape: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var wash: Color { theme.ink(0.10) }
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        // A square with a square hole: the nested contour empties out.
        let outer = [Vector2(140, 48), Vector2(330, 48),
                     Vector2(330, 238), Vector2(140, 238)]
        let hole = [Vector2(196, 104), Vector2(274, 104),
                    Vector2(274, 182), Vector2(196, 182)]
        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawShape(Shape(outer: outer, holes: [hole]))
        noStroke()
        fill(accent)
        for p in hole { drawCircle(center: p, radius: 4) }
        label("a hole: nested contours empty out", 236, 260)

        // The closure form: a curved outline traced with the pen.
        fill(wash)
        stroke(ink)
        strokeWeight(3)
        let trace = [Vector2(520, 210), Vector2(600, 78),
                     Vector2(706, 120), Vector2(768, 60)]
        drawShape { p in
            p.move(to: trace[0])
            p.curve(to: trace[1])
            p.curve(to: trace[2])
            p.quadCurve(to: trace[3], control: Vector2(760, 150))
            p.line(to: Vector2(790, 216))
            p.close()
        }
        noStroke()
        fill(accent)
        for p in trace { drawCircle(center: p, radius: 4) }
        label("drawShape { }: a curved outline, closed and filled", 646, 260)
    }

    func label(_ text: String, _ x: Double, _ y: Double) {
        noStroke()
        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText(text, x, y)
    }
}
