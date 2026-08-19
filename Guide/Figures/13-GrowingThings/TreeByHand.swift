// figure: frame=0
//
// Guide figure (Chapter 13): a fractal tree by hand. One function draws a
// trunk, then calls itself twice, tilted left and right, a little shorter,
// until the branches run out of depth. The whole tree is nine levels of the
// same idea, swaying gently.
import Ollin

final class TreeByHand: Sketch {
    @Param("Angle", 0.1...0.6) var angle = 0.32
    @Param("Shrink", 0.55...0.78) var shrink = 0.7

    override func draw() {
        background(Color(hex: 0x101318))
        stroke(Color(hex: 0xE8DCC0))
        strokeCap(.round)

        withState {
            translate(width / 2, height - 110)
            branch(length: 235, depth: 9)
        }
    }

    func branch(length: Double, depth: Int) {
        guard depth > 0 else { return }
        let sway = sin(time * 0.8 + Double(depth)) * 0.02
        strokeWeight(Double(depth) * 0.9)
        drawLine(0, 0, 0, -length)
        translate(0, -length)
        withState {
            rotate(-angle + sway)
            branch(length: length * shrink, depth: depth - 1)
        }
        withState {
            rotate(angle * 1.15 + sway)
            branch(length: length * shrink, depth: depth - 1)
        }
    }
}
