// figure: frame=0
//
// Guide payoff (Chapter 6): a wall of rosettes. One grid supplies the blocks,
// the transforms place and turn each one, symmetry folds a single crooked arm
// into a medallion, and a clip trims the arms at the rim. Every click re-rolls
// the wall.
import Ollin

final class RoseWall: Sketch {
    @Param("Columns", 2...8) var columns = 5
    @Param("Seed", 1...9999) var wallSeed = 7
    @Param("Mirrored") var mirrored = true

    let paper = Color(hex: 0xF2EDE4)
    let ink = Color(hex: 0x232020)
    let ramp = Ramp([
        Color(hex: 0xE4572E), Color(hex: 0xF3A712),
        Color(hex: 0x2A9D8F), Color(hex: 0x3D348B),
    ])

    override func draw() {
        seed(wallSeed)
        background(paper)

        let blocks = grid(columns: columns, rows: columns, padding: 60, gutter: 18)
        for cell in blocks.cells {
            let radius = cell.frame.width / 2
            let folds = [5, 6, 8, 12][Int(random(4))]
            let reach = Double(cell.column + cell.row) / Double(2 * columns - 2)

            withState {
                translate(cell.center)
                rotate(random(.tau))
                scale(random(0.88, 1.0))

                noStroke()
                fill(ramp.color(at: reach))
                drawCircle(0, 0, radius)

                withClip(Circle(center: .zero, radius: radius)) {
                    symmetry(folds, mirrored: mirrored)
                    drawArm(radius: radius)
                }
            }
        }
    }

    // One arm, deliberately lopsided, drawn well past the edge of its block so
    // the clip is what gives every medallion its rim.
    func drawArm(radius: Double) {
        stroke(paper)
        strokeWeight(radius * 0.07)
        strokeCap(.round)
        drawLine(radius * 0.10, 0, radius * 1.30, 0)
        drawLine(radius * 0.58, 0, radius * 0.94, -radius * 0.34)

        noStroke()
        fill(paper)
        drawCircle(radius * 1.30, 0, radius * 0.10)
        fill(ink)
        drawCircle(radius * 0.94, -radius * 0.34, radius * 0.05)
        drawCircle(radius * 0.36, 0, radius * 0.045)
    }

    override func mousePressed() {
        wallSeed += 1
    }
}
