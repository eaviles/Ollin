// figure: frame=0
//
// Guide figure: the reader's very first sketch. One circle, dead center.
import Ollin

final class FirstCircle: Sketch {
    override func draw() {
        background(.white)
        fill(Color(hex: 0x2B2B2B))
        drawCircle(width / 2, height / 2, 200)
    }
}
