import Ollin
import OllinSamplePhotos

/// A photograph rebuilt as a print halftone screen.
///
/// `drawHalftone` lays the classic rotated dot grid over an image and sizes
/// every dot so its ink area matches the tone underneath: midtones become
/// even fields of marks, and shadows grow dots that merge into checkered
/// diamonds. The screen swings through a quarter turn over the loop, and the
/// picture never wavers, because tone lives in dot area, not dot placement.
/// A quarter turn is a whole lap: the square lattice repeats every 90
/// degrees, so the loop closes seamlessly.
///
/// The dots are real circles, so `--export-svg` writes them as vectors, the
/// pen-plotter reading of the same frame. Hold the mouse for the inverted
/// screen: light marks sized by brightness on a dark canvas.
///
/// The source is one of the bundled sample photographs, an elderly woman in a
/// yellow scarf, whose face runs through every tone the screen can render. A
/// halftone reads one value per dot, so it is handed a small copy.
@main
final class Halftone: Sketch {
    override var loopDuration: Double? { 12 }

    private var source = Image(width: 1, height: 1)

    override func setup() {
        source = SamplePhoto.scarf.load().resized(width: 360, height: 360)
    }

    override func draw() {
        let angle = Double.pi / 4 + loopProgress(over: 12) * .pi / 2
        noStroke()
        if mouseIsPressed {
            background(Color(hex: 0x14161C))
            fill(Color(hex: 0xF2EDE2))
            drawHalftone(source, pitch: 13, angle: angle, inverted: true)
        } else {
            background(Color(hex: 0xF2EDE2))
            fill(Color(hex: 0x22242C))
            drawHalftone(source, pitch: 13, angle: angle)
        }
        drawCaption("area-exact dots on a turning screen; hold the mouse for the inverted reading")
    }
}
