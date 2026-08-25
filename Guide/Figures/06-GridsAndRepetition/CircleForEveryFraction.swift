// figure: frame=0 themed
//
// Guide diagram (Chapter 6): Ford circles. On the left the fractions with
// denominators up to four, labeled, on the right the same picture once every
// denominator up to twelve has arrived, with the new circles dropping into the
// gaps the old ones left.
import Ollin
import OllinDiagram

final class CircleForEveryFraction: Sketch {
    override var canvasSize: CanvasSize { .size(880, 460) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    let accent = Color(hex: 0xE07A5F)
    var soft: Color { theme.ink(0.12) }
    var note: Color { darkTheme ? Color(hex: 0xE8E5E1, alpha: 0.62) : Color(hex: 0x6E6A63) }

    override func draw() {
        background(paper)

        let left = Rectangle(x: 64, y: 74, width: 340, height: 200)
        let right = Rectangle(x: 476, y: 74, width: 340, height: 200)

        panel(left, order: 4, labeled: true)
        panel(right, order: 12, labeled: false)

        frame(left, title: "denominators up to 4")
        frame(right, title: "denominators up to 12")

        fill(ink)
        noStroke()
        textSize(21)
        textAlign(.center, .top)
        drawText("every fraction gets a circle, and they never overlap", width / 2, 320)
        textSize(17)
        fill(note)
        drawText("two of them touch when their fractions are neighbors: ps - qr is 1 or -1",
                 width / 2, 354)
        drawText("a small denominator is a big circle, and a fraction worth approximating with",
                 width / 2, 382)
    }

    func panel(_ box: Rectangle, order: Int, labeled: Bool) {
        // The biggest circles are half the width across, so they run past the top
        // and the sides of the panel. Clipping is what the classic picture does.
        withClip(box) {
            strokeWeight(1.5)
            for ford in fordCircles(order: order, in: box) {
                let small = ford.fraction.denominator > 4
                fill(small ? Color(hex: 0xE07A5F, alpha: 0.16)
                           : theme.ink(0.07))
                stroke(small ? accent : ink)
                drawCircle(ford.circle)
            }
        }

        // The line the circles all sit on.
        stroke(ink)
        strokeWeight(2)
        drawLine(box.x, box.y + box.height, box.x + box.width, box.y + box.height)

        guard labeled else { return }
        noStroke()
        fill(ink)
        textSize(15)
        textAlign(.center, .top)
        for ford in fordCircles(order: order, in: box) where ford.fraction.denominator <= 4 {
            drawText("\(ford.fraction)", ford.circle.center.x, box.y + box.height + 8)
        }
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
