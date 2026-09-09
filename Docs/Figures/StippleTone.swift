// figure: frame=0 themed
//
// Docs diagram (Generators/Stippling.md): weighted-Voronoi stippling. Left,
// the source picture, one of the bundled sample photographs. Right, its
// stipple: a fixed budget of dots whose local density carries the tone,
// packed tight in the dark of the head and the braid, spread thin across
// the plain ground.
import Ollin
import OllinDiagram
import OllinSamplePhotos

final class StippleTone: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }
    var source: Image?
    var dots: [Vector2] = []

    let left = Rectangle(x: 110, y: 56, width: 300, height: 300)
    let right = Rectangle(x: 470, y: 56, width: 300, height: 300)

    override func setup() {
        seed(7)
        let picture = SamplePhoto.profile.load().resized(width: 300, height: 300)
        source = picture
        dots = stipple(of: picture, count: 3400, in: right)
    }

    override func draw() {
        background(paper)
        guard let source else { return }

        drawImage(source, in: left)

        noStroke()
        fill(ink)
        for d in dots {
            drawCircle(center: d, radius: 1.8)
        }

        frame(left, title: "the picture")
        frame(right, title: "the stipple: one dot budget")

        noStroke()
        fill(ink)
        textFont(OutlineFont.system)
        textSize(21)
        textAlign(.center, .top)
        drawText("shadow packs the dots tight, highlight spreads them out",
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
