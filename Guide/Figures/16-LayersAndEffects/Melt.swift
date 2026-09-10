// figure: frame=0 themed
//
// Guide diagram (Chapter 16): the luminance melt. A simple painted scene
// drawn into a layer, then the same layer filtered. One displacement field
// both warps the noise the filter draws with and shifts where it samples the
// picture, which is why the result reads as dyed rather than only smeared.
import Ollin
import OllinDiagram
import OllinSamplePhotos

final class Melt: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }

    private var photograph = Image(width: 1, height: 1)

    override func setup() {
        photograph = SamplePhoto.headland.load()
    }

    override func draw() {
        background(paper)

        let left = Rectangle(x: 110, y: 56, width: 300, height: 300)
        let right = Rectangle(x: 470, y: 56, width: 300, height: 300)

        // Square, because the panels are: a canvas-shaped layer drawn into a
        // square panel would squeeze the photograph rather than crop it.
        let scene = makeRenderTarget(width: 600, height: 600)
        withTarget(scene) { paint(in: Rectangle(x: 0, y: 0, width: 600, height: 600)) }

        drawImage(scene.image, in: left)
        drawImage(scene.filtered(.melt(phase: 2.4)).image, in: right)

        frame(left, title: "the layer")
        frame(right, title: "filtered(.melt())")

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("brightness decides where the picture runs",
                 width / 2, 396)
    }

    /// A dusk landscape: one of the bundled photographs, a headland in
    /// silhouette under a graded sky, covering the square without stretching.
    func paint(in frame: Rectangle) {
        drawImage(photograph, in: frame, fit: .cover)
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
