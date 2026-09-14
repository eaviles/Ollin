// figure: frame=90
//
// Guide figure (Chapter 19): the Ising model at three temperatures from one
// seeded start, 180 sweeps in. Left, cold (1.5): the field has magnetized into
// domains that keep coarsening. Middle, the critical temperature (about 2.27):
// clusters at every size, patches inside patches. Right, hot (4): the heat wins
// and the field is noise. Three fields with one seed, every one read every
// frame so all three step together.
import Ollin

final class IsingFigure: Sketch {
    override var canvasSize: CanvasSize { .size(940, 330) }

    private var cold: SimField!
    private var critical: SimField!
    private var hot: SimField!

    private let spins = Ramp(stops: [(0.0, Color(hex: 0x1B2A4A)),
                                     (1.0, Color(hex: 0xF4E9D3))])

    override func setup() {
        cold = makeSimField(.ising(temperature: 1.5, sweeps: 2, seed: 6), scale: 0.3)
        critical = makeSimField(.ising(sweeps: 2, seed: 6), scale: 0.3)
        hot = makeSimField(.ising(temperature: 4, sweeps: 2, seed: 6), scale: 0.3)
    }

    override func draw() {
        background(Color(hex: 0x0A0B0E))
        let side = 290.0, top = 12.0
        let fields: [(SimField, Double, String)] = [
            (cold, 12, "cold, 1.5"),
            (critical, 325, "critical, 2.27"),
            (hot, 638, "hot, 4"),
        ]
        for (field, x, caption) in fields {
            // A field is the canvas's own shape; the square panel takes its
            // left part, which is a square of spins.
            let scale = side / height
            withClip(Rectangle(x: x, y: top, width: side, height: side)) {
                drawImage(field.filtered(.gradientMap(spins)).image, x, top,
                          width * scale, height * scale)
            }
            noStroke()
            fill(Color(white: 0.7))
            textSize(13)
            textAlign(.center)
            drawText(caption, x + side / 2, top + side + 20)
        }
    }
}
