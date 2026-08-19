// figure: frame=600
//
// Guide payoff (Chapter 18): the organism. A reaction-diffusion culture
// seeded by a scatter (and, live, by whatever you draw with the mouse),
// stretched and recolored through a gradient map, its relief lit as wet skin.
import Ollin

final class Organism: Sketch {
    var dish: SimField?

    override func setup() {
        seed(7)
        toneMap(.aces, exposure: 1.15)
    }

    override func draw() {
        background(Color(hex: 0x04070B))
        if dish == nil { dish = simField(.reactionDiffusion(feed: 0.055, kill: 0.062), scale: 0.5) }
        guard let dish else { return }

        withField(dish) {
            noStroke()
            fill(.white)
            if frameCount == 1 {                       // the culture's first spores
                for p in poissonDisk(radius: 170) { drawCircle(center: p, radius: 5) }
            }
            if mouseIsPressed {                        // and whatever you draw
                drawCircle(mouseX, mouseY, 9)
            }
        }

        let skin = Ramp([Color(hex: 0x06131F), Color(hex: 0x0E4C5C),
                         Color(hex: 0x3FA893), Color(hex: 0xF2E3C2)])
        drawImage(dish.filtered(.levels(blackPoint: 0.16, whitePoint: 0.42))
                      .filtered(.gradientMap(skin))
                      .filtered(.relight(.liquid, height: 1.4)).image, 0, 0)
    }
}
