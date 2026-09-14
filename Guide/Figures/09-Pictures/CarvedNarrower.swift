// figure: frame=0 themed
//
// Guide diagram (Chapter 9): seam carving. A Guanajuato alley, one of the
// bundled photographs, at its own width, squeezed to seven tenths of it, and
// carved to the same width by removing the cheapest paths down. The squeeze
// narrows everything together; the carve takes the plain sky and leaves the
// walls the width they were.
import Ollin
import OllinDiagram
import OllinSamplePhotos

final class CarvedNarrower: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }
    var source: Image?
    var carved: Image?

    override func setup() {
        let picture = SamplePhoto.alley.load().resized(width: 300, height: 300)
        source = picture
        carved = picture.seamCarved(toWidth: 210)
    }

    override func draw() {
        background(paper)
        guard let source, let carved else { return }

        let full = Rectangle(x: 92, y: 96, width: 240, height: 240)
        let squeezed = Rectangle(x: 392, y: 96, width: 168, height: 240)
        let narrowed = Rectangle(x: 620, y: 96, width: 168, height: 240)

        drawImage(source, in: full)
        drawImage(source, in: squeezed)
        drawImage(carved, in: narrowed)

        frame(full, title: "the picture")
        frame(squeezed, title: "squeezed to 70%")
        frame(narrowed, title: "carved to 70%")

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("the squeeze narrows everything; the carve takes the empty sky",
                 width / 2, 386)
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
