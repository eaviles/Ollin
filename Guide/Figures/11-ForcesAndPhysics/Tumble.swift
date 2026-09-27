// figure: frame=240
//
// Guide listing (Chapter 11): rigid bodies. Boxes and discs start in a loose
// grid at random angles, fall, tip, and come to rest in a jumble with every
// corner intact. Each box is drawn by moving to its position and turning to
// its angle, so the rotation on screen is the solver's own.
import Ollin
import OllinPhysics

final class Tumble: Sketch {
    let world = World()
    var boxes: [Body] = []
    var discs: [Body] = []
    let boxSize = Vector2(130, 46)
    let discRadius = 36.0

    let palette = [
        Color(hex: 0xE07A5F), Color(hex: 0xF2CC8F),
        Color(hex: 0x81B29A), Color(hex: 0x8187B9),
    ]

    override func setup() {
        seed(5)
        world.gravity = Vector2(0, 2200)
        world.bounds = bounds
        for i in 0 ..< 24 {
            let start = Vector2(90 + Double(i % 6) * 180, 80 + Double(i / 6) * 150)
            if i % 4 == 3 {
                discs.append(world.addBody(.circle(radius: discRadius), at: start, friction: 0.5))
            } else {
                let box = world.addBody(.box(width: boxSize.x, height: boxSize.y),
                                        at: start, friction: 0.6)
                box.angle = random(0, .tau)
                boxes.append(box)
            }
        }
        noStroke()
    }

    override func draw() {
        background(Color(hex: 0x101318))
        world.advance(by: deltaTime)

        for (i, box) in boxes.enumerated() {
            withState {
                translate(box.position)
                rotate(box.angle)
                fill(palette[i % palette.count])
                drawRect(center: .zero, width: boxSize.x, height: boxSize.y,
                         cornerRadius: 4)
            }
        }
        fill(Color(hex: 0xF2EFE8))
        for disc in discs {
            drawCircle(center: disc.position, radius: discRadius)
        }
    }
}
