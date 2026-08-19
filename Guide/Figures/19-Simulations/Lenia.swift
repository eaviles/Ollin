// figure: frame=220
//
// Guide diagram (Chapter 19): Lenia, the continuous Game of Life. A dense soup
// of soft marks, seeded once, grown for a few hundred steps into the smooth
// pulsing blobs and rings the model is known for.
import Ollin

final class Lenia: Sketch {
    var dish: SimField?

    override func setup() {
        seed(11)
    }

    override func draw() {
        background(Color(hex: 0x05070C))
        if dish == nil { dish = simField(.lenia(radius: 13), scale: 0.55) }
        guard let dish else { return }

        withField(dish) {
            if frameCount == 1 {
                // Lenia needs a *dense* soup: sparse mass starves and fades.
                noStroke()
                for _ in 0 ..< 90 {
                    let c = Vector2(random(width), random(height))
                    for _ in 0 ..< 16 {
                        fill(Color(white: random(0.5, 1.0)))
                        drawCircle(c.x + random(-46, 46), c.y + random(-46, 46),
                                   random(14, 30))
                    }
                }
            }
        }

        let skin = Ramp([Color(hex: 0x05070C), Color(hex: 0x1B3A5B),
                         Color(hex: 0x3FA893), Color(hex: 0xF2E3C2)])
        drawImage(dish.filtered(.gradientMap(skin)).image, 0, 0)
    }
}
