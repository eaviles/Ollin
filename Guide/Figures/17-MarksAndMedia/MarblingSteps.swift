// figure: frame=0 themed
//
// Guide diagram (Chapter 15): the four marbling moves. The same bull's-eye
// of alternating drops, then a single stylus pulled down through it, then a
// whole comb of teeth, then a stirred vortex. Every panel is vector outlines
// that were bent, never redrawn.
import Ollin
import OllinDiagram

final class MarblingSteps: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }
    let navy = Color(hex: 0x2B3440)
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)

        let titles = ["drop", "tine", "comb", "swirl"]
        for i in 0 ..< 4 {
            let panel = Rectangle(x: 25 + Double(i) * 212, y: 68,
                                  width: 194, height: 260)
            let center = Vector2(panel.x + panel.width / 2,
                                 panel.y + panel.height / 2)

            var bath = Marbling(spacing: 3)
            let rings = 11
            for ring in 0 ..< rings {
                let radius = map(Double(ring), 0, Double(rings - 1), 86, 11)
                let color = ring == rings - 1 ? accent
                    : (ring.isMultiple(of: 2) ? navy : paper)
                bath.drop(at: center, radius: radius, color: color)
            }

            switch i {
            case 1:
                bath.tine(through: center, direction: .unitY,
                          strength: 78, falloff: 46)
            case 2:
                bath.comb(through: Vector2(panel.x, center.y), direction: .unitY,
                          spacing: 42, strength: 64, falloff: 12)
            case 3:
                // Off-center on purpose: a vortex stirred at the bull's-eye's
                // own middle rotates every ring onto itself and shows nothing.
                bath.swirl(at: center + Vector2(34, -30),
                           strength: 190, falloff: 54)
            default:
                break
            }

            withClip(panel) {
                noStroke()
                drawMarbling(bath)
            }
            frame(panel, title: titles[i])
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("one bath, four tools: every pattern is a bent outline",
                 width / 2, 366)
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
        drawText(title, r.x + 2, r.y - 20)
    }
}
