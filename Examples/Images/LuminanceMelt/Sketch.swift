import Ollin
import OllinSamplePhotos

/// A photograph poured through the luminance melt.
///
/// `.melt` runs one displacement field twice: it warps a noise field's own
/// domain, and the same displacement shifts where the picture is sampled, so
/// the image smears along the field's currents while its brightness steers
/// the field back. Everything reads through a four-stop palette, which is
/// why the melt looks dyed rather than merely warped: the picture survives
/// as light and shadow, not as its own colors.
///
/// Hold the mouse to see the untouched photograph; release and it pours
/// again. The field churns in place (the sway is a few slow, bounded sines),
/// so the melt drifts without ever sliding away.
///
/// The picture is one of the bundled sample photographs, a young woman in a
/// white lace headdress over a dark embroidered blouse: strong tonal shapes,
/// which is what the melt reads.
@main
final class LuminanceMelt: Sketch {
    private var source = Image(width: 1, height: 1)

    override func setup() {
        seed(7)
        source = SamplePhoto.portrait.load()
    }

    override func draw() {
        background(.black)
        let painting = makeRenderTarget()
        withTarget(painting) {
            drawImage(source, in: canvasRectangle)
        }
        let shown = mouseIsPressed ? painting : painting.filtered(.melt(phase: time))
        drawImage(shown.image, in: canvasRectangle)
        drawCaption("one displacement warps the field and liquifies the picture; hold the mouse for the source")
    }
}
