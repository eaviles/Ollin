import Ollin
import OllinSamplePhotos

/// **XDoG** draws a picture as pen and ink: a line wherever the picture has an
/// edge, solid ink where it is dark, and paper everywhere else. Underneath, two
/// blurs of the brightness are subtracted (the difference of Gaussians), pushed
/// hard over the tone, and cut at a threshold. The blur is taken across each edge
/// and its response gathered along the edge, following the edge's own direction,
/// which is what makes the lines run continuous instead of breaking into speckle.
///
/// The picture is one of the bundled sample photographs, an elderly woman in a
/// yellow scarf: the kind of face the technique was published on, every line of
/// it an edge for the filter to find. `Radius` is the line scale, `Sharpening`
/// how far the edges are pushed over the tone, `Threshold` where paper turns to
/// ink, `Softness` the ramp under it (0 is a two-tone print, larger keeps a gray
/// wash below the cut), and `Flow` how far along an edge the response is
/// gathered (set it to 0 and watch the lines fray). `Compare` shows the
/// photograph itself on the left half.
@main
final class InkDrawing: Sketch {

    @Param("Radius", 0.5 ... 6, icon: "scribble", group: "Line") var radius = 2.0
    @Param("Sharpening", 0 ... 40, icon: "bolt", group: "Line") var sharpening = 20.0
    @Param("Flow", 0 ... 12, icon: "wind", group: "Line") var flow = 3.0
    @Param("Threshold", 0 ... 1, icon: "circle.lefthalf.filled", group: "Cut") var threshold = 0.3
    @Param("Softness", 0 ... 0.5, icon: "drop", group: "Cut") var softness = 0.2
    @Param(icon: "paintbrush.pointed", group: "Colors") var ink = Color(hex: 0x1B1040)
    @Param(icon: "doc", group: "Colors") var paper = Color(hex: 0xF3EBDD)
    @Param(icon: "rectangle.split.2x1", group: "View") var compare = false

    private var photograph = Image(width: 1, height: 1)

    override func setup() {
        photograph = SamplePhoto.scarf.load()
    }

    override func draw() {
        background(paper)
        let scene = makeRenderTarget()
        withTarget(scene) { drawImage(photograph, in: canvasRectangle, fit: .cover) }

        let inked = scene.filtered(.xdog(radius: radius, sharpening: sharpening,
                                          threshold: threshold, softness: softness,
                                          flow: flow, foreground: ink, background: paper))
        drawImage(inked.image, 0, 0)

        if compare {
            withClip(Rectangle(x: 0, y: 0, width: width / 2, height: height)) {
                drawImage(scene.image, 0, 0)
            }
            stroke(ink)
            strokeWeight(3)
            drawLine(width / 2, 0, width / 2, height)
        }
    }
}
