// figure: frame=150
//
// Guide diagram (Chapter 19): SmoothLife, Life's own rule on a continuous field.
// A scatter of the paper's glider seeds, each a disc a little under the radius
// with a notch bitten out of one side, run for a hundred and fifty generations
// into the sliding gliders, pulsing rings, and split colonies of the glider regime.
import Ollin

final class SmoothLife: Sketch {
    var dish: SimField?
    let fieldScale = 0.35
    let reach = 14

    override func setup() {
        seed(7)
    }

    override func draw() {
        background(Color(hex: 0x07090E))
        if dish == nil { dish = makeSimField(.smoothLife(radius: reach), scale: fieldScale) }
        guard let dish else { return }

        withField(dish) {
            if frameCount == 1 {
                noStroke()
                let r = Double(reach) / fieldScale
                for _ in 0 ..< 16 {
                    let c = Vector2(random(width), random(height))
                    let facing = random(.pi * 2)
                    fill(.white)
                    drawCircle(c.x, c.y, r * 0.86)
                    fill(.black)
                    drawCircle(c.x + cos(facing) * r * 0.43, c.y + sin(facing) * r * 0.43, r * 0.33)
                }
            }
        }

        let skin = Ramp([Color(hex: 0x07090E), Color(hex: 0x24406B),
                         Color(hex: 0x4FB3A6), Color(hex: 0xF4E6C3)])
        drawImage(dish.filtered(.gradientMap(skin)).image, 0, 0)
    }
}
