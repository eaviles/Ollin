import Ollin
import OllinSamplePhotos

/// **Brushwork** lays the picture on as paint. Each pixel becomes the average of
/// the flattest of eight overlapping sectors of a brush around it, so detail
/// flattens into patches while edges stay crisp. The brush is an ellipse drawn
/// out along whatever edge runs through the pixel, so the patches read as
/// strokes that follow the picture's own contours rather than square dabs.
///
/// The picture is one of the bundled sample photographs, a woman before a wall
/// of marigolds: the petals flatten into dabs of one orange, the strokes run
/// with their edges, and the face keeps its lines. `Radius` is the brush size,
/// `Stretch` how far a stroke is drawn out along an edge (1 keeps the brush
/// round, and the patches turn blocky), and `Sharpness` how decisively the
/// flattest patch wins (0 is only a blur). `Compare` shows the photograph itself
/// on the left half.
@main
final class Brushwork: Sketch {

    @Param("Radius", 1 ... 12, icon: "paintbrush", group: "Brush") var radius = 6.0
    @Param("Stretch", 1 ... 16, icon: "arrow.left.and.right", group: "Brush") var stretch = 4.0
    @Param("Sharpness", 0 ... 16, icon: "bolt", group: "Brush") var sharpness = 8.0
    @Param(icon: "rectangle.split.2x1", group: "View") var compare = false

    private var photograph = Image(width: 1, height: 1)

    override func setup() {
        photograph = SamplePhoto.marigolds.load()
    }

    override func draw() {
        background(.black)
        let scene = makeRenderTarget()
        withTarget(scene) { drawImage(photograph, in: canvasRectangle, fit: .cover) }

        let painted = scene.filtered(.brushwork(radius: radius, stretch: stretch,
                                                sharpness: sharpness))
        drawImage(painted.image, 0, 0)

        if compare {
            withClip(Rectangle(x: 0, y: 0, width: width / 2, height: height)) {
                drawImage(scene.image, 0, 0)
            }
            stroke(.white)
            strokeWeight(3)
            drawLine(width / 2, 0, width / 2, height)
        }
    }
}
