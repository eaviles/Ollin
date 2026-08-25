// figure: frame=0 themed
//
// Guide diagram (Chapter 1): the canvas is not the window. The canvas is a
// fixed grid of pixels your drawing is measured in; the window is a scaled
// view of it. Making the window smaller does not make the picture smaller.
import Ollin
import OllinDiagram

final class CanvasVsWindow: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.45) }
    var faint: Color { theme.ink(0.14) }
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)

        let canvas = Rectangle(x: 70, y: 84, width: 300, height: 300)
        let window = Rectangle(x: 530, y: 154, width: 160, height: 160)

        art(in: canvas)
        art(in: window)

        // The canvas: labeled in real pixels.
        noFill()
        stroke(ink)
        strokeWeight(2)
        drawRect(canvas)
        noStroke()
        fill(soft)
        textSize(14)
        textAlign(.left, .bottom)
        drawText("(0, 0)", canvas.x, canvas.y - 6)
        textAlign(.right, .top)
        drawText("(1080, 1080)", canvas.x + canvas.width, canvas.y + canvas.height + 6)

        // The window: a view of the same thing, drawn smaller.
        noFill()
        stroke(ink)
        strokeWeight(2)
        drawRect(window)
        // A title bar, so it reads as a window rather than another canvas.
        noStroke()
        fill(faint)
        drawRect(window.x, window.y - 16, window.width, 16)
        fill(soft)
        drawCircle(window.x + 9, window.y - 8, 3)

        noStroke()
        fill(ink)
        textSize(17)
        textAlign(.center, .top)
        drawText("the canvas: 1080 by 1080 pixels", canvas.x + canvas.width / 2, 408)
        drawText("the window: a scaled view", window.x + window.width / 2, 408)

        // The relationship between them.
        stroke(accent)
        strokeWeight(1.6)
        noFill()
        drawLine(canvas.x + canvas.width + 14, canvas.y + 40, window.x - 14, window.y - 6)
        drawLine(canvas.x + canvas.width + 14, canvas.y + canvas.height - 40,
                 window.x - 14, window.y + window.height + 6)
        noStroke()
        fill(accent)
        textSize(15)
        textAlign(.center, .middle)
        drawText("scaled to fit", (canvas.x + canvas.width + window.x) / 2, 234)

        fill(soft)
        textSize(15)
        textAlign(.center, .top)
        drawText("`width` and `height` say 1080 either way, so the drawing never changes",
                 width / 2, 440)
    }

    /// A small composition, drawn identically into whatever rectangle it gets.
    func art(in r: Rectangle) {
        noStroke()
        fill(Color(hex: 0x1B2A4A))
        drawRect(r)
        fill(Color(hex: 0xE4572E))
        drawCircle(center: r.point(u: 0.5, v: 0.42), radius: r.width * 0.2)
        fill(Color(hex: 0xF2CC8F))
        drawCircle(center: r.point(u: 0.68, v: 0.66), radius: r.width * 0.1)
    }
}
