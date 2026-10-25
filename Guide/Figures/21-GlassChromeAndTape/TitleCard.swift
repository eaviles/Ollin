// figure: frame=90
//
// Guide payoff (Chapter 21): a title card. A word is lettered in airbrushed
// chrome from its silhouette in a band of its own, laid over the sky of a
// bundled photograph of a headland at dusk, and the card is taken through a
// cheap lens (a barrel and color split toward the edges) and played off a worn
// videotape, with a print's hairline scratches over it. The chrome's horizon
// and the tape both run on time.
import Ollin
import OllinSamplePhotos

final class TitleCard: Sketch {
    var photo = Image(width: 1, height: 1)

    override func setup() {
        photo = SamplePhoto.headland.load()
    }

    override func draw() {
        // The word as a silhouette in a band of its own, lettered in chrome by
        // the filter, which reads the band's height as its sky and its floor.
        let band = Int(height * 0.3)
        let word = makeRenderTarget(width: Int(width), height: band)
        withTarget(word) {
            noStroke()
            fill(.white)
            textFont(.systemBold)
            textSize(Double(band) * 0.78)
            textAlign(.center, .middle)
            drawText("OLLIN", width / 2, Double(band) / 2)
        }

        // The card: the shore at dusk, with the chrome word over its sky.
        let card = makeRenderTarget()
        withTarget(card) {
            drawImage(photo, in: canvasRectangle, fit: .cover)
            drawImage(word.filtered(.chrome(phase: time * 0.5)).image, 0, height * 0.2)
        }

        // Through a cheap lens: a barrel, and color pulled apart toward the edges.
        let lens = card
            .filtered(.lensDistortion(amount: 0.16, fillsFrame: true))
            .filtered(.chromaticAberration(amount: 0.02, mode: .lens(radius: 0.3, falloff: 2)))
        drawImage(lens.image, 0, 0)

        // Off a worn tape, with a print's scratches over it.
        postProcess(.vhs(phase: time))
        drawImage(generate(.scratches(phase: time, seed: 3)).image, 0, 0)
    }
}
