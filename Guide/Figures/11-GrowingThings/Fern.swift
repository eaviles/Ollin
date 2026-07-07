// figure: frame=0
//
// Guide figure (Chapter 11): the plant preset drawn whole. One rewriting
// grammar, five rounds, a turtle, and nothing else.
import Ollin

final class Fern: Sketch {
    override func draw() {
        background(Color(hex: 0x101318))
        stroke(Color(hex: 0x9AD9A0))
        strokeWeight(1.6)
        strokeCap(.round)
        drawLSystem(.plant, iterations: 5)
    }
}
