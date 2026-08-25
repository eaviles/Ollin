// figure: frame=0 themed
//
// Docs diagram (Drawing/LocalAverages.md): the adaptive threshold's window
// must be large enough to hold both ink and paper. The same page of thick
// marks is cut twice, for real: with the window smaller than the marks their
// middles see nothing but ink, decide that is what paper looks like there,
// and come out hollow; a wide window keeps them solid.
import Ollin
import OllinDiagram

final class HollowStroke: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }

    override func draw() {
        background(paper)

        // One page of marks thicker than the narrow window: a solid disc,
        // a fat ring, and a heavy bar.
        let page = renderTarget(width: 300, height: 300)
        withTarget(page) {
            background(.white)
            noStroke()
            fill(.black)
            drawCircle(82, 90, 52)
            drawRect(40, 200, 220, 56)
            noFill()
            stroke(.black)
            strokeWeight(40)
            drawCircle(212, 96, 54)
        }

        let narrow = page.filtered(.adaptiveThreshold(window: 20))
        let wide = page.filtered(.adaptiveThreshold(window: 160))

        let left = Rectangle(x: 110, y: 56, width: 300, height: 300)
        let right = Rectangle(x: 470, y: 56, width: 300, height: 300)
        drawImage(narrow.image, in: left)
        drawImage(wide.image, in: right)

        frame(left, title: "window 20: smaller than the marks")
        frame(right, title: "window 160: wide enough")

        noStroke()
        fill(ink)
        textFont(OutlineFont.system)
        textSize(21)
        textAlign(.center, .top)
        drawText("the middle of a thick mark sees only ink, and calls it paper",
                 width / 2, 396)
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textFont(OutlineFont.system)
        textSize(17)
        textAlign(.left, .middle)
        drawText(title, r.x, r.y - 20)
    }
}
