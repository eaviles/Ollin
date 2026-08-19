// figure: frame=90
//
// Guide listing (Chapter 17): the Game of Life on a SimField, seeded with a
// random soup on the first frame and left to run. By frame 90 the soup has
// burned down to still lifes, blinkers, and the odd glider.
import Ollin

final class LifeField: Sketch {
    var life: SimField?

    override func setup() {
        seed(12)
    }

    override func draw() {
        background(.black)
        if life == nil { life = simField(.gameOfLife(), scale: 0.08) }   // chunky cells
        guard let life else { return }

        withField(life) {
            noStroke()
            fill(.white)
            if frameCount == 1 {                       // a random soup, once
                for _ in 0 ..< 700 {
                    drawCircle(width * 0.5 + random(-260, 260),
                               height * 0.5 + random(-260, 260), 7)
                }
            }
        }
        drawImage(life.image, 0, 0)
    }
}
