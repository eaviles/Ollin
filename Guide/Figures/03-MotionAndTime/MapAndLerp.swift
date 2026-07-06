// figure: frame=0
//
// Guide diagram: map and lerp. Top: map carries a value from one range to
// another by keeping its fraction along. Bottom: lerp walks from a to b as
// t runs 0 to 1.
import Ollin

final class MapAndLerp: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.28)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(21)

        // Top: map. Two number lines; the dot keeps its fraction along.
        let lineLeft = 200.0, lineRight = 680.0
        let fromY = 110.0, toY = 210.0
        let fraction = 0.75                     // sin(time) at 0.5 in -1...1

        func numberLine(_ y: Double, _ lo: String, _ hi: String) {
            stroke(ink)
            strokeWeight(2.5)
            drawLine(lineLeft, y, lineRight, y)
            drawLine(lineLeft, y - 8, lineLeft, y + 8)
            drawLine(lineRight, y - 8, lineRight, y + 8)
            noStroke()
            fill(ink)
            textAlign(.right, .middle)
            drawText(lo, lineLeft - 16, y)
            textAlign(.left, .middle)
            drawText(hi, lineRight + 16, y)
        }
        numberLine(fromY, "-1", "1")
        numberLine(toY, "60", "200")

        let dotX = lineLeft + fraction * (lineRight - lineLeft)
        stroke(accent)
        strokeWeight(2)
        var y = fromY + 12
        while y < toY - 14 {
            drawLine(dotX, y, dotX, min(y + 10, toY - 14))
            y += 20
        }
        noStroke()
        fill(accent)
        drawCircle(dotX, fromY, 9)
        drawCircle(dotX, toY, 9)
        fill(ink)
        textAlign(.left, .middle)
        drawText("0.5", dotX + 14, fromY - 24)
        drawText("130", dotX + 14, toY + 26)
        textAlign(.center, .top)
        drawText("map(0.5, -1, 1, 60, 200) keeps the fraction along: 75% in, 75% out",
                 width / 2, 268)

        // Bottom: lerp. A walk from a to b as t runs 0...1.
        let aX = 200.0, bX = 680.0, walkY = 420.0
        stroke(faint)
        strokeWeight(2.5)
        drawLine(aX, walkY, bX, walkY)
        noStroke()
        textAlign(.center, .bottom)
        for i in 0...4 {
            let t = Double(i) / 4
            let x = aX + t * (bX - aX)
            if i == 1 {
                fill(accent)
                drawCircle(x, walkY, 10)
                fill(ink)
                drawText("t = 0.25", x, walkY - 22)
            } else {
                fill(ink)
                drawCircle(x, walkY, 7)
                if i == 0 { drawText("a  (t = 0)", x, walkY - 22) }
                if i == 4 { drawText("b  (t = 1)", x, walkY - 22) }
            }
        }
        fill(ink)
        textAlign(.center, .top)
        drawText("lerp(a, b, t): the point t of the way from a to b",
                 width / 2, walkY + 36)
    }
}
