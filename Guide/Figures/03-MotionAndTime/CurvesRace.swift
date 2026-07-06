// figure: gif duration=4 fps=25 width=600
//
// Guide figure: four dots run the same out-and-back trip on different
// curves. Same start, same finish, same four seconds; only the spacing of
// the journey differs.
import Ollin

final class CurvesRace: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.28)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(21)

        // Out and back once per 4-second loop.
        let trip = pingPong(over: 4)

        drawLane(y: 120, label: "linear", t: trip)
        drawLane(y: 230, label: "easeInQuad", t: Easing.easeInQuad(trip))
        drawLane(y: 340, label: "easeOutQuad", t: Easing.easeOutQuad(trip))
        drawLane(y: 450, label: "smoothstep", t: smoothstep(0, 1, trip), hero: true)
    }

    func drawLane(y: Double, label: String, t: Double, hero: Bool = false) {
        let startX = 260.0, endX = 810.0
        stroke(faint)
        strokeWeight(2)
        drawLine(startX, y, endX, y)
        drawLine(startX, y - 10, startX, y + 10)
        drawLine(endX, y - 10, endX, y + 10)
        noStroke()
        fill(ink)
        textAlign(.left, .middle)
        drawText(label, 60, y)
        if hero {
            fill(accent)
        }
        drawCircle(startX + t * (endX - startX), y, 17)
    }
}
