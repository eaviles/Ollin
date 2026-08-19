// figure: frame=0 probe
//
// Guide figure: the Appendix C translated sketch. One breathing circle,
// dead center, shown at its first frame.
import Ollin

final class Pulse: Sketch {
    override func draw() {
        background(.white)
        fill(Color(hex: 0x2050C8))
        drawCircle(width / 2, height / 2, 240 + sin(time * 1.8) * 80)
    }
}
