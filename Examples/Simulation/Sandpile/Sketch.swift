import Ollin

/// The **Abelian sandpile**, the toppling automaton that named self-organized
/// criticality, running as a `.sandpile` SimField on the classic protocol: drop a
/// mountain of sand on one spot, then watch it collapse, four grains at a time, into
/// the famous circular figure with its self-similar lobes. Each stable count wears
/// its own color (0...3 grains), the top of the ramp catches cells mid-topple, and
/// the collapse reads as a molten core crystallizing outward into lacework. Hold the
/// mouse to pour a torrent somewhere else, release to let it settle, and watch two
/// piles negotiate their border. `pace` is the toppling passes per frame: turn it
/// down to watch single avalanche waves roll, up to hurry the collapse.
@main
final class Sandpile: Sketch {
    private var pile: SimField!

    /// Radius of the dropped mountain, in canvas points.
    @Param(4 ... 40, icon: "triangle") var mountain = 16.0
    /// Toppling passes per frame: an avalanche front moves one cell per pass,
    /// so this is the pacing dial.
    @Param(1 ... 128, icon: "speedometer") var pace = 64.0

    /// One color per stable grain count, the classic way these piles are pictured:
    /// the field stores its count in quarters, so 0, 1, 2, 3 grains sit at exactly
    /// 0, ¼, ½, ¾ and the top of the ramp catches cells flashing mid-topple.
    private let counts = Ramp(stops: [(0.00, Color(hex: 0x10141F)),
                                      (0.25, Color(hex: 0x2C6E91)),
                                      (0.50, Color(hex: 0xE3A857)),
                                      (0.75, Color(hex: 0xF2E9DC)),
                                      (1.00, .white)])

    override func setup() {
        pile = simField(.sandpile(pour: 1024), scale: 0.5)
    }

    override func draw() {
        background(.black)
        pile.sim = .sandpile(pour: 1024, topplings: Int(pace))

        withField(pile) {
            noStroke()
            fill(.white)
            if frameCount == 1 {                       // the opening mountain
                drawCircle(width / 2, height / 2, mountain)
            }
            if mouseIsPressed {                        // a torrent while held
                drawCircle(mouseX, mouseY, mountain)
            }
        }

        drawImage(pile.filtered(.gradientMap(counts)).image, 0, 0)
        drawCaption("Abelian sandpile · a mountain collapsing four grains at a time · hold to pour another")
    }
}
