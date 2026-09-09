// figure: frame=0 themed
//
// Guide diagram (Chapter 16): the coherence-enhancing filter. A photograph
// (one of the bundled sample photographs) drawn into a layer, then the same
// layer through `.shock()`: soft shading snapped into flat regions with crisp
// edges, the lace drawn out along its own flow.
import Ollin
import OllinDiagram
import OllinSamplePhotos

final class FlatRegions: Sketch {
    override var canvasSize: CanvasSize { .size(880, 400) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }

    var photograph = Image(width: 1, height: 1)

    override func setup() {
        photograph = SamplePhoto.portrait.load()
    }

    override func draw() {
        background(paper)

        let left = Rectangle(x: 90, y: 92, width: 330, height: 180)
        let right = Rectangle(x: 460, y: 92, width: 330, height: 180)

        // The layer is the panel's own size, so the shock's reach and the flow's
        // length stay the pixels the filter counts.
        let scene = makeRenderTarget(width: Int(left.width), height: Int(left.height))
        withTarget(scene) {
            drawImage(photograph, in: Rectangle(x: 0, y: 0, width: left.width, height: left.height), fit: .cover)
        }

        drawImage(scene.image, in: left)
        drawImage(scene.filtered(.shock()).image, in: right)

        frame(left, title: "the layer")
        frame(right, title: "filtered(.shock())")

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("smoothed along the flow, sharpened across it", width / 2, 312)
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
