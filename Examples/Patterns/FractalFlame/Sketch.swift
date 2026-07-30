import Ollin

/// A fractal flame, developed from its density histogram.
///
/// The chaos game plays a handful of affine maps, each finished with a
/// nonlinear variation (a swirl, a spherical inversion, a fold), while every
/// pixel counts its visits. The display maps those counts through a
/// logarithm, so the bright spine and the faintest veils share one image,
/// and the color comes from *which* transforms carried the orbit there, not
/// from position.
///
/// The render is progressive, the way flames are meant to be watched: each
/// frame feeds the renderer another slice of samples and redraws, so the
/// image rises out of the noise and keeps refining. Each `variation` seed
/// rolls a different random flame; click or press any key for the next one.
/// Some rolls are duds, which is part of the game: reroll until one sings.
@main
final class FractalFlame: Sketch {
    private var renderer: Ollin.FractalFlame.Renderer?
    private var picture: Image?

    override func setup() {
        rollFlame()
    }

    override func draw() {
        background(.black)
        if let renderer {
            renderer.accumulate(samples: 120_000)
            // Developing the histogram costs as much as sampling it, so the
            // picture refreshes every few frames while samples keep landing.
            if picture == nil || frameCount % 4 == 0 {
                picture = renderer.image()
            }
            if let picture {
                drawImage(picture, in: canvasRectangle)
            }
            let taken = Double(renderer.samples) / 1_000_000
            drawCaption(String(format: "variation %d, %.1fM samples and rising; click or press a key to reroll",
                               variation, taken))
        }
    }

    override func mousePressed() { reroll() }
    override func keyPressed() { reroll() }

    private func reroll() {
        seed(Int.random(in: 1 ... 99_999))
        rollFlame()
    }

    private func rollFlame() {
        var source = SplitMix64(seed: UInt64(variation))
        let flame = Ollin.FractalFlame.random(using: &source)
        renderer = Ollin.FractalFlame.Renderer(flame, width: 560, height: 560,
                                               seed: variation)
        picture = nil
    }
}
