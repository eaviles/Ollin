import Ollin

/// **Shape grammar**: a window frame, one rule, and a lattice that cuts itself.
///
/// The rule is a single sentence. *A cell becomes two cells, cut apart by one
/// straight line drawn between two of its edges, with the two parts about equal
/// in area.* Nothing says which edges, or where on them, so the rule stands for
/// every lattice it could make rather than for this one.
///
/// Watch it build. Each sweep offers every cell to the rule, and a cell too
/// small to be worth cutting is left alone, which is what brings the design to
/// a stop. Traditional ice-ray lattices were cut this way for real, one fitted
/// stick at a time: divide the area into large and equal spots, then keep
/// dividing until the pieces are the size you wanted.
///
/// The second rule is what turns the cells into bars. It pulls each cell's
/// outline inward by the same distance all the way round, and the ring left
/// over is the wood.
///
/// Try it: `balance` is how uneven a cut may leave the two parts. Hold it near
/// zero and every cut halves the area, which reads as regular and machined.
/// Open it up and the cuts go where they like, which is where the cracked-ice
/// look comes from.
@main
final class ShapeGrammarSketch: Sketch {
    @Param(1_500 ... 40_000, icon: "square.grid.3x3") var cellSize = 7_000.0
    @Param(0 ... 0.7, icon: "scalemass") var balance = 0.3
    @Param(0 ... 16, icon: "square.dashed") var barWidth = 6.0

    private let paper = Color(hex: 0x121016)
    private let wood = Color(hex: 0x8A5A34)
    private let sky = Color(hex: 0xD9CFAF)

    private var frame = Rectangle(x: 0, y: 0, width: 1, height: 1)
    private var grammar = ShapeGrammar(start: ShapeGrammar.Piece("cell", Rectangle(x: 0, y: 0, width: 1, height: 1)),
                                       rules: [])
    private var cells: [ShapeGrammar.Piece] = []
    private var source = SplitMix64(seed: 1)
    private var asked = (cell: 0.0, balance: 0.0)
    private var run = 0
    private var restingFrames = 0

    override func setup() {
        frame = Rectangle(center: center, width: width * 0.82, height: height * 0.82)
        start()
    }

    override func draw() {
        background(paper)
        if asked != (cellSize, balance) { start() }

        // One sweep every few frames, so the rule can be watched working.
        if frameCount % 6 == 0 {
            let grown = grammar.step(cells, source: &source)
            if grown.count == cells.count {
                restingFrames -= 1
                if restingFrames < 0 { run += 1; start() }
            } else {
                cells = grown
            }
        }

        // The bars are what is left of each cell once its middle is taken out.
        // The second rule carries no weight, so it is only reached for a cell
        // with no room for a full bar, which would otherwise stay solid wood.
        let panes = ShapeGrammar(start: cells,
                                 rules: [.inset("cell", by: barWidth, into: "pane"),
                                         .inset("cell", by: barWidth * 0.3, into: "pane",
                                                weight: 0)])
            .run(generations: 1, seed: 0)

        noStroke()
        fill(wood)
        drawRect(corner: frame.topLeft, width: frame.width, height: frame.height)
        fill(sky)
        for pane in panes where pane.label == "pane" { drawPolygon(pane.corners) }

        caption()
    }

    private func start() {
        source = SplitMix64(seed: UInt64(run &* 977 &+ 13))
        grammar = ShapeGrammar.iceRay(in: frame, minimumArea: cellSize, balance: balance)
        cells = grammar.start
        asked = (cellSize, balance)
        restingFrames = 40
    }

    private func caption() {
        let corners = cells.map(\.corners.count)
        let threes = corners.filter { $0 == 3 }.count
        let fours = corners.filter { $0 == 4 }.count
        let fives = corners.filter { $0 == 5 }.count
        fill(sky.withAlpha(0.8))
        textFont(.system); textSize(width * 0.019); textAlign(.center, .bottom)
        drawText("\(cells.count) cells: \(threes) triangles, \(fours) quadrilaterals, \(fives) pentagons",
                 width / 2, height - width * 0.045)
    }
}
