import Ollin
import Foundation

// The joint ops of the SDF combinators: where a smooth union melts two shapes together,
// the chamfer ops join them with a crisp 45° bevel and the stairs ops with a staircase of
// steps (machined seams instead of organic blends). A 2×3 contact sheet: each cell joins
// the same circle + diamond pair with one op, the joint size breathing so the seam's
// character shows. Colors stay a crisp pick per side (no melt), which is the point.
@main
final class CombinatorsJoinery: Sketch {
    override func draw() {
        background(Color(hex: 0x14161a))
        let r = 26.0 + sin(time * 1.4) * 14.0   // the joint size breathes

        let cells = grid(columns: 3, rows: 2, padding: 90, gutter: 30).cells
        let labels = ["chamfer union", "stairs union", "chamfer subtract",
                      "stairs subtract", "chamfer intersect", "stairs intersect"]
        for cell in cells {
            // Two bars crossing as a plus: every seam meets at a right angle and no
            // parallel edges sit within the joint radius, the ops' working envelope
            // (grazing or near-parallel surfaces echo the joint pattern past the seam).
            let a = SDF.rect(width: 280, height: 130).at(0, -10)
                .colored(Color(hex: 0x46c2ff))
            let b = SDF.rect(width: 130, height: 280).at(10, 0)
                .colored(Color(hex: 0xffb454))
            let joined: SDF
            switch cell.row * 3 + cell.column {
            case 0: joined = a.chamferUnion(b, radius: r)
            case 1: joined = a.stairsUnion(b, radius: r, steps: 4)
            case 2: joined = a.chamferSubtract(b, radius: r)
            case 3: joined = a.stairsSubtract(b, radius: r, steps: 4)
            case 4: joined = a.chamferIntersect(b, radius: r)
            default: joined = a.stairsIntersect(b, radius: r, steps: 4)
            }
            withState {
                translate(cell.center)
                stroke(Color(white: 0.85))
                strokeWeight(2)
                drawSDF(joined)
            }
            fill(Color(white: 0.55))
            textSize(17)
            textAlign(.center)
            drawText(labels[cell.row * 3 + cell.column],
                     at: Vector2(cell.center.x, cell.frame.bottomLeft.y - 8))
        }
    }
}
