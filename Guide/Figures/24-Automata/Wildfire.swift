// figure: frame=120
//
// Guide payoff (Chapter 24): the wildfire. A forest planted by percolation,
// each cell a tree with a chance just past the critical probability, then
// struck once in the middle. The forest fire rule burns it with growth and
// lightning both at zero, and it reads the same four neighbors percolation
// joins clusters by, so the fire runs through exactly one cluster, the one the
// strike landed in, and goes out wherever the trees stop touching. A hundred
// and twenty steps in, the burned cluster is a pale scar of ash with its edges
// still alight, the clusters the fire never reached stand green inside and
// around it, and the ground nothing was planted on stays dark. A press starts
// another fire wherever the mouse is.
import Ollin

final class Wildfire: Sketch {
    let cells = 216                                   // the forest, in cells on a side
    var forest: Percolation!
    var woods: SimField!

    let ground = Color(hex: 0x0B0A09)                 // where nothing was planted
    let colors = Ramp(stops: [(0.0, Color(hex: 0x8A8178)),     // burned: ash
                              (0.5, Color(hex: 0x2B5F3D)),     // a tree
                              (1.0, Color(hex: 0xFFB547))])    // burning

    override func setup() {
        seed(9)
        forest = percolation(columns: cells, rows: cells,
                             probability: Percolation.criticalProbability + 0.02)
        woods = makeSimField(.forestFire(growth: 0, lightning: 0, neighborhood: .vonNeumann),
                             scale: Double(cells) / width, edge: .clamped)
    }

    override func draw() {
        let side = width / Double(cells)              // one cell, in canvas pixels
        noStroke()
        withField(woods) {
            if frameCount == 1 {
                fill(Color(white: 0.5))               // plant every open cell
                for k in 0 ..< forest.clusterCount {
                    for cell in forest.cellRects(of: k, in: bounds) { drawRect(cell) }
                }
                fill(.white)                          // and strike the middle, once
                drawCircle(width / 2, height / 2, side * 3)
            }
            if mouseIsPressed {                       // or wherever you press
                fill(.white)
                drawCircle(mouseX, mouseY, side * 2)
            }
        }

        background(ground)
        drawImage(woods.filtered(.gradientMap(colors)).image, 0, 0)
        fill(ground)                                  // cover the cells never planted
        for row in 0 ..< cells {
            for column in 0 ..< cells where !forest.isOpen(column: column, row: row) {
                drawRect(Double(column) * side, Double(row) * side, side, side)
            }
        }
        postProcess(.bloom(threshold: 0.6, amount: 1.5, radius: 12))
    }
}
