// figure: frame=1200
//
// Guide diagram (Chapter 19): the Abelian sandpile, run on the classic
// protocol: drop a mountain of sand on one spot (a single heavy pour on the
// first frame), then let it collapse until every cell is stable. The relaxed
// pile is colored one color per grain count (the state stores counts in
// quarters, so the ramp puts a color at each quarter). The circular figure,
// the fourfold symmetry, and the self-similar lacework all emerge from the
// four-grain toppling rule; none of them are drawn. Ink-on-cream so the pile
// reads like a printed map.
import Ollin

final class SandpileFigure: Sketch {
    override var canvasSize: CanvasSize { .square(560) }

    private var pile: SimField!
    private let counts = Ramp(stops: [(0.00, Color(hex: 0xF5F1E6)),
                                      (0.25, Color(hex: 0xA9C0CF)),
                                      (0.50, Color(hex: 0xD9A441)),
                                      (0.75, Color(hex: 0x2E3440)),
                                      (1.00, Color(hex: 0xB3402A))])

    override func setup() {
        pile = makeSimField(.sandpile(pour: 1024, topplings: 128), scale: 1)
    }

    override func draw() {
        background(Color(hex: 0xF5F1E6))
        withField(pile) {
            if frameCount == 1 {   // the mountain: ~320k grains, dropped once
                noStroke()
                fill(.white)
                drawCircle(width / 2, height / 2, 10)
            }
        }
        drawImage(pile.filtered(.gradientMap(counts)).image, 0, 0)
    }
}
