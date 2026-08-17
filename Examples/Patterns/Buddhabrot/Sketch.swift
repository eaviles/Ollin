import Ollin

/// The Buddhabrot, exposed live.
///
/// The Mandelbrot set's escaping orbits, plotted instead of discarded: random
/// plane points are tested with the familiar z = z² + c loop, and each one
/// that escapes brightens every pixel its orbit visited. The density of all
/// those visits, developed like a photographic plate, is the ghostly seated
/// figure. Three iteration caps expose the red, green, and blue channels at
/// different orbit lengths, so short-lived orbits haze the background blue
/// while the longest ones draw the figure's red spine.
///
/// The render is progressive, the way a plate this deep has to be: each frame
/// feeds the renderer another slice of orbit samples and redevelops, so the
/// figure rises out of the noise for as long as you leave it running. Click
/// or press any key to switch between the false-color and grayscale plates.
@main
final class Buddhabrot_Example: Sketch {
    private var renderer: Ollin.Buddhabrot.Renderer?
    private var picture: Image?
    private var falseColor = true

    override func setup() {
        startPlate()
    }

    override func draw() {
        background(.black)
        if let renderer {
            renderer.accumulate(samples: 20_000)
            // Developing costs a few accumulate slices, so the plate refreshes
            // every few frames while samples keep landing.
            if picture == nil || frameCount % 6 == 0 {
                picture = renderer.image()
            }
            if let picture {
                drawImage(picture, in: canvasRectangle)
            }
            let taken = Double(renderer.samples) / 1_000_000
            let plate = falseColor ? "three exposures as RGB" : "one exposure, gray"
            drawCaption(String(format: "%@, %.1fM orbits and rising; click to switch",
                               plate, taken))
        }
    }

    override func mousePressed() { switchPlate() }
    override func keyPressed() { switchPlate() }

    private func switchPlate() {
        falseColor.toggle()
        startPlate()
    }

    private func startPlate() {
        let plate = Ollin.Buddhabrot(iterations: falseColor ? [5000, 500, 50] : [1000])
        renderer = Ollin.Buddhabrot.Renderer(plate, width: 560, height: 560, seed: 7)
        picture = nil
    }
}
