// figure: frame=0 themed
//
// Guide diagram: frame-rate independence. A fixed step per frame covers twice
// the ground on a display that draws twice as often; a step scaled by
// deltaTime lands in the same place on any display.
import Ollin

final class DeltaTime: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var faint: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.28) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }

    override func draw() {
        background(paper)
        textSize(21)

        let left = 90.0
        let unit = 2.1        // pixels per motion unit

        func strip(_ y: Double, frames: Int, stepPerFrame: Double, label: String) {
            noStroke()
            fill(ink)
            textAlign(.left, .bottom)
            drawText(label, left, y - 18)
            stroke(faint)
            strokeWeight(2)
            drawLine(left, y, left + Double(frames) * stepPerFrame * unit, y)
            noStroke()
            for i in 0...frames {
                fill(ink)
                drawCircle(left + Double(i) * stepPerFrame * unit, y, 2.3)
            }
            let endX = left + Double(frames) * stepPerFrame * unit
            stroke(accent)
            strokeWeight(3)
            drawLine(endX, y - 12, endX, y + 12)
        }

        // The two matching finish lines, linked by a faint guide.
        stroke(faint)
        strokeWeight(2)
        drawLine(left + 180 * unit, 132, left + 180 * unit, 380)

        // One second of motion, three ways.
        strip(120, frames: 60, stepPerFrame: 3, label: "x += 3 each frame, on a 60 fps display")
        strip(250, frames: 120, stepPerFrame: 3, label: "the same sketch on a 120 fps display: twice as far")
        strip(380, frames: 120, stepPerFrame: 180.0 / 120.0,
              label: "x += 180 * deltaTime, on the 120 fps display: back in step")

        noStroke()
        fill(ink)
        textAlign(.center, .top)
        drawText("each strip is one second; a dot per frame, the mark where x ends up",
                 width / 2, 470)
    }
}
