// figure: frame=0 themed
//
// Guide diagram (Chapter 9): how an autostereogram carries depth. A flat repeat
// on top, the same pattern with a shortened repeat under it, and the reading the
// two eyes make of each.
import Ollin

final class DepthInARepeat: Sketch {
    override var canvasSize: CanvasSize { .size(880, 460) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    let accent = Color(hex: 0xE07A5F)
    var soft: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.12) }
    var note: Color { darkTheme ? Color(hex: 0xE8E5E1, alpha: 0.62) : Color(hex: 0x6E6A63) }

    override func draw() {
        background(paper)
        seed(4)

        let left = 110.0, span = 660.0
        strip(y: 110, x: left, width: span, repeatWidth: 110, shortened: nil)
        strip(y: 250, x: left, width: span, repeatWidth: 110, shortened: 84)

        label("a flat repeat: both eyes pair the same marks, and it reads as flat",
              at: Vector2(left, 88))
        label("a shorter repeat in the middle: that stretch reads as nearer",
              at: Vector2(left, 228))

        fill(ink)
        noStroke()
        textSize(21)
        textAlign(.center, .top)
        drawText("shorten the repeat and the pair reads as closer", width / 2, 366)
        textSize(17)
        fill(note)
        drawText("so a depth map becomes a picture, and the surface is never drawn at all",
                 width / 2, 400)
    }

    /// One strip of a repeating pattern, with the repeat marked underneath. When
    /// `shortened` is given, the middle third repeats at that spacing instead.
    func strip(y: Double, x: Double, width across: Double, repeatWidth: Double, shortened: Double?) {
        let height = 46.0
        let nearFrom = x + across * 0.36, nearTo = x + across * 0.64

        // One repeat's worth of marks, copied along at whichever spacing applies.
        var marks: [(Double, Double, Double)] = []      // offset, size, tone
        for _ in 0 ..< 26 {
            marks.append((random(0, repeatWidth), random(3, 7), random(0.25, 0.8)))
        }

        noStroke()
        withClip(Rectangle(x: x, y: y, width: across, height: height)) {
            fill(Color(white: 0.94))
            drawRect(Rectangle(x: x, y: y, width: across, height: height))
            var at = x
            while at < x + across + repeatWidth {
                let inside = shortened != nil && at >= nearFrom && at < nearTo
                let step = inside ? (shortened ?? repeatWidth) : repeatWidth
                for (offset, size, tone) in marks where offset < step {
                    fill(Color(white: 1 - tone))
                    drawCircle(at + offset, y + 8 + (offset * 1.7).truncatingRemainder(dividingBy: 30),
                               size / 2)
                }
                at += step
            }
        }
        noFill()
        stroke(soft)
        strokeWeight(1.5)
        drawRect(Rectangle(x: x, y: y, width: across, height: height))

        // The spacing, marked under the strip.
        strokeWeight(2)
        stroke(shortened == nil ? ink : Color(white: 0.55))
        bracket(from: x + 8, to: x + 8 + repeatWidth, y: y + height + 14)
        if let shortened {
            stroke(accent)
            bracket(from: nearFrom + 4, to: nearFrom + 4 + shortened, y: y + height + 14)
            noStroke()
            fill(accent)
            textSize(14)
            textAlign(.left, .middle)
            drawText("shorter", nearFrom + shortened + 14, y + height + 14)
        }
    }

    func bracket(from a: Double, to b: Double, y: Double) {
        drawLine(a, y, b, y)
        drawLine(a, y - 5, a, y + 5)
        drawLine(b, y - 5, b, y + 5)
    }

    func label(_ text: String, at point: Vector2) {
        noStroke()
        fill(ink)
        textSize(17)
        textAlign(.left, .middle)
        drawText(text, point.x, point.y)
    }
}
