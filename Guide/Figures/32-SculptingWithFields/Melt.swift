// figure: frame=0
//
// Guide listing (Chapter 32): the melt in two dimensions. An orange circle and
// a blue rounded rectangle merge through the smooth minimum, their colors
// blending across the seam. At frame 0 the melt width `k` sits midway, at 65
// canvas points.
import Ollin

final class Melt: Sketch {
    override func draw() {
        background(Color(hex: 0x101318))
        noStroke()
        let k = 20 + (sin(time) * 0.5 + 0.5) * 90

        let blob = SDF.circle(radius: 130).colored(Color(hex: 0xE4572E))
            .smoothUnion(SDF.rect(width: 240, height: 140, cornerRadius: 28)
                .colored(Color(hex: 0x3A6EA5))
                .at(130, 40), k: k)

        drawSDF(blob.at(width / 2, height / 2))
    }
}
