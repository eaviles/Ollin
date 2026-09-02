// figure: frame=600
//
// Guide diagram (Chapter 19): the falling-sand automaton. A short shelf over
// a pool, and one tap above it: grains fall from the tap, pile on the shelf,
// slump off both ends once the heap is wider than the shelf, and sink through
// the pool to its floor while the water they push aside rises to the top. Nothing here is a heap by design; the cone, the slump, and the
// leveled water all come out of one rule applied to 2x2 blocks. The tap jitters
// on a fixed formula, so the figure renders the same every time. One tone per
// material: cream is empty, blue is water, ochre is sand, slate is wall.
import Ollin

final class FallingSandFigure: Sketch {
    override var canvasSize: CanvasSize { .square(560) }

    private var sand: SimField!
    private let materials = Ramp(stops: [(0.000, Color(hex: 0xF5F1E6)),
                                         (1 / 3, Color(hex: 0x6F9BC4)),
                                         (2 / 3, Color(hex: 0xD9A441)),
                                         (1.000, Color(hex: 0x2E3440))])

    override func setup() {
        sand = makeSimField(.fallingSand(passes: 16, friction: 0.3), scale: 0.5)
    }

    override func draw() {
        background(Color(hex: 0xF5F1E6))
        withField(sand) {
            noStroke()
            if frameCount == 1 {
                // A short shelf under the tap, and a pool across the floor.
                fill(SandMaterial.wall.color)
                drawRect(width * 0.41, height * 0.4, width * 0.18, 8)
                fill(SandMaterial.water.color)
                drawRect(0, height * 0.74, width, height * 0.26)
            }
            if frameCount <= 480 {
                // The tap: a few grains a frame, jittered on a fixed formula.
                fill(SandMaterial.sand.color)
                let wobble = sin(Double(frameCount) * 0.7) * 9 + sin(Double(frameCount) * 1.9) * 4
                drawCircle(width * 0.5 + wobble, 10, 2)
            }
        }
        drawImage(sand.filtered(.gradientMap(materials)).image, 0, 0)
    }
}
