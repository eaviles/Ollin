import Ollin
import OllinSamplePhotos

/// **Shock** flattens a picture into regions with crisp edges that follow its
/// own flow, the coherence-enhancing filter. Each round smooths the layer along
/// the direction of least change at every pixel and sharpens it across that
/// direction with a shock filter: where the brightness bends toward bright a
/// pixel takes the brightest pixel within reach, where it bends toward dark the
/// darkest, so soft shading snaps into flat bands and everything along an edge
/// is drawn out into one coherent stroke. No color is invented; every pixel is a
/// blend, along its own contour, of colors the layer holds.
///
/// The picture is one of the bundled sample photographs, a young woman in a lace
/// headdress and an embroidered blouse: the lace and the embroidery snap into
/// flat shapes, the skin into a few bands, and the edges between them stay
/// crisp. The filter counts in pixels, so the photograph is drawn into a layer
/// at `Scale` of the canvas: at 0.5 the shock's reach and the flow's length are
/// twice what they would be at full size, which is what makes the bands read on
/// a big canvas. `Rounds` is how many times the smoothing and the shock are
/// applied, and so the level of abstraction (2 is a light clean-up, 10 a
/// poster). `Flow` is how far along the flow each round smooths, `Radius` how
/// far across an edge the shock reaches, `Smoothing` the blur on the brightness
/// the shock reads its sign from (raise it and the lace stops making edges), and
/// `Threshold` the bend under which nothing is sharpened. `Compare` shows the
/// layer itself on the left half.
@main
final class Coherence: Sketch {

    @Param("Rounds", 1 ... 10, icon: "arrow.clockwise", group: "Filter") var rounds = 3
    @Param("Flow", 1 ... 16, icon: "wind", group: "Filter") var flow = 6.0
    @Param("Radius", 1 ... 6, icon: "bolt", group: "Filter") var radius = 2.0
    @Param("Smoothing", 0 ... 6, icon: "drop", group: "Filter") var smoothing = 0.0
    @Param("Threshold", 0 ... 0.02, icon: "circle.lefthalf.filled", group: "Filter") var threshold = 0.005
    @Param("Scale", 0.25 ... 1, icon: "arrow.down.right.and.arrow.up.left", group: "Layer") var layerScale = 0.5
    @Param(icon: "rectangle.split.2x1", group: "View") var compare = false

    private var photograph = Image(width: 1, height: 1)

    override func setup() {
        photograph = SamplePhoto.portrait.load()
    }

    override func draw() {
        background(Color(hex: 0x1C1A1F))
        let scene = makeRenderTarget(scale: layerScale)
        withTarget(scene) { drawImage(photograph, in: canvasRectangle, fit: .cover) }

        let flattened = scene.filtered(.shock(iterations: rounds, flow: flow, radius: radius,
                                              smoothing: smoothing, threshold: threshold))
        drawImage(flattened.image, 0, 0)

        if compare {
            withClip(Rectangle(x: 0, y: 0, width: width / 2, height: height)) {
                drawImage(scene.image, 0, 0)
            }
            stroke(Color(hex: 0xF3EBDD))
            strokeWeight(3)
            drawLine(width / 2, 0, width / 2, height)
        }
    }
}
