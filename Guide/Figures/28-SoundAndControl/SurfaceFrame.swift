// figure: frame=0 themed
//
// Guide diagram (Chapter 28): one frame from a tangible surface. The tracker
// sends a set for what moved, then the whole alive list, then the frame number
// that commits them. The next frame drops a touch by leaving it out of the
// list, which is the part that surprises people: nothing says "ended".
import Ollin
import OllinDiagram

final class SurfaceFrame: Sketch {
    override var canvasSize: CanvasSize { .size(880, 560) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.4) }
    var soft: Color { theme.ink(0.6) }
    var accent: Color { theme.accent }
    var card: Color { darkTheme ? Color(hex: 0x2A2724) : .white }

    override func draw() {
        background(paper)

        messages(x: 46, y: 56, w: 400, h: 178, title: "one frame, sent many times a second",
                 lines: ["/tuio/2Dcur set 12 0.30 0.35 …",
                         "/tuio/2Dcur set 13 0.70 0.70 …",
                         "/tuio/2Dcur alive 12 13",
                         "/tuio/2Dcur fseq 4218"])
        surface(x: 546, y: 46, size: 200, touches: [(12, Vector2(0.30, 0.35)), (13, Vector2(0.70, 0.70))],
                gone: nil)
        arrow(from: Vector2(452, 145), to: Vector2(538, 145))

        messages(x: 46, y: 300, w: 400, h: 140, title: "the next frame, with one finger lifted",
                 lines: ["/tuio/2Dcur alive 13",
                         "/tuio/2Dcur fseq 4219"])
        surface(x: 546, y: 290, size: 200, touches: [(13, Vector2(0.70, 0.70))],
                gone: Vector2(0.30, 0.35))
        arrow(from: Vector2(452, 370), to: Vector2(538, 370))

        noStroke()
        fill(soft)
        textSize(19)
        textAlign(.center, .top)
        drawText("nothing says a touch ended: it is simply missing from the alive list", width / 2, 505)
    }

    // MARK: Pieces

    func messages(x: Double, y: Double, w: Double, h: Double, title: String, lines: [String]) {
        fill(card)
        stroke(faint)
        strokeWeight(1.5)
        drawRect(x, y, w, h, cornerRadius: 10)
        noStroke()
        fill(soft)
        textSize(17)
        textAlign(.left, .top)
        drawText(title, x + 22, y + 16)
        fill(ink)
        textSize(17)
        for (index, line) in lines.enumerated() {
            drawText(line, x + 22, y + 54 + Double(index) * 28)
        }
    }

    func surface(x: Double, y: Double, size: Double,
                 touches: [(id: Int, at: Vector2)], gone: Vector2?) {
        fill(card)
        stroke(faint)
        strokeWeight(1.5)
        drawRect(x, y, size, size, cornerRadius: 6)

        noStroke()
        fill(theme.ink(0.35))
        textSize(14)
        textAlign(.left, .top)
        drawText("0, 0", x + 8, y + 6)
        textAlign(.right, .bottom)
        drawText("1, 1", x + size - 8, y + size - 6)

        // A touch that has left, drawn as the ring it used to fill.
        if let gone {
            noFill()
            stroke(theme.ink(0.3))
            strokeWeight(2)
            drawCircle(center: Vector2(x + gone.x * size, y + gone.y * size), radius: 15)
        }

        for touch in touches {
            let at = Vector2(x + touch.at.x * size, y + touch.at.y * size)
            noStroke()
            fill(theme.accent(0.25))
            drawCircle(center: at, radius: 22)
            fill(accent)
            drawCircle(center: at, radius: 9)
            fill(ink)
            textSize(15)
            textAlign(.left, .bottom)
            drawText("\(touch.id)", at.x + 16, at.y - 12)
        }
    }

    func arrow(from a: Vector2, to b: Vector2) {
        let dir = (b - a).normalized
        stroke(accent)
        strokeWeight(3)
        drawLine(a, b - dir * 12)
        noStroke()
        fill(accent)
        drawPolygon([b, b - dir * 15 + dir.perpendicular * 6,
                        b - dir * 15 - dir.perpendicular * 6])
    }
}
