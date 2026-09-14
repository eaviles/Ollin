// figure: frame=0 themed
//
// Guide diagram (Chapter 9): a picture turned into line work. One stipple of
// the bundled profile photograph joined two ways: one closed tour that never
// lifts the pen, and the minimum spanning tree, which branches. The cutoff
// calls the plain ground behind the profile paper, so every dot goes to the
// face and the ground stays empty.
import Ollin
import OllinDiagram
import OllinSamplePhotos

final class PictureAsLines: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }
    var dots: [Vector2] = []
    var tour: Contour?
    var tree: [Contour] = []

    override func setup() {
        seed(5)
        let source = SamplePhoto.profile.load().resized(width: 160, height: 160)
        let first = Rectangle(x: 25, y: 66, width: 262, height: 262)
        // The tour visits every dot once, so its points are the stipple
        // itself, and the tree is built over those same dots.
        let loop = singleLine(of: source, points: 2400, in: first, cutoff: 0.62)
        dots = loop.points
        tour = loop
        tree = spanningTree(through: dots)
    }

    override func draw() {
        background(paper)

        let panels = [Rectangle(x: 25, y: 66, width: 262, height: 262),
                      Rectangle(x: 309, y: 66, width: 262, height: 262),
                      Rectangle(x: 593, y: 66, width: 262, height: 262)]

        noStroke()
        fill(ink)
        drawCircles(dots, radius: 1.5)

        withState {
            translate(284, 0)
            noFill()
            stroke(ink)
            strokeWeight(0.8)
            if let tour { drawPolyline(tour.points, closed: tour.isClosed) }
        }

        withState {
            translate(568, 0)
            noFill()
            stroke(ink)
            strokeWeight(0.8)
            for chain in tree { drawPolyline(chain.points) }
        }

        frame(panels[0], title: "the stipple")
        frame(panels[1], title: "one unbroken tour")
        frame(panels[2], title: "the spanning tree")

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("the same 2,400 dots, joined into a loop and into branches",
                 width / 2, 364)
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
