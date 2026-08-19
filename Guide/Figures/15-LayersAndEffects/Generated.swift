// figure: frame=0
//
// Guide listing (Chapter 15): a layer from nowhere. A procedural generator
// fills the layer (no drawing at all), and a design filter lays the result
// onto a sheet of paper.
import Ollin

final class Generated: Sketch {
    override func draw() {
        let sky = generate(.meshGradient(colors: [Color(hex: 0xE4572E), Color(hex: 0x2B6C8C),
                                                  Color(hex: 0xE8B44A), Color(hex: 0x7C3B5E)],
                                         phase: 5.1))
        drawImage(sky.filtered(.paperTexture()).image, 0, 0)
    }
}
