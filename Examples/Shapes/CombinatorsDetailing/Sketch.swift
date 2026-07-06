import Ollin
import Foundation

// The detailing ops of the SDF combinators, rounding out the joint family: the columns
// trio joins, cuts, or intersects through a row of circular ribs (a fluted seam); pipe
// keeps only a round bead along two outlines' crossing; engrave scores a v-notch into a
// body along another's outline; groove cuts a flat channel and tongue raises its mating
// ridge. A 4×2 contact sheet over the same crossing-bars pair, the rib count stepping
// over time; the last cell fits a tongue into its groove.
@main
final class CombinatorsDetailing: Sketch {
    override func draw() {
        background(Color(hex: 0x14161a))
        let count = 3 + Int(time * 0.7) % 4   // the rib count steps 3…6

        let cells = grid(columns: 4, rows: 2, padding: Insets(top: 120, right: 40, bottom: 120, left: 40),
                         gutter: 24).cells
        let labels = ["columns union", "columns subtract", "columns intersect", "pipe",
                      "engrave", "groove", "tongue", "tongue + groove"]
        for cell in cells {
            let a = SDF.rect(width: 200, height: 96).colored(Color(hex: 0x46c2ff))
            let b = SDF.rect(width: 96, height: 200).at(x: 8, y: 0).colored(Color(hex: 0xffb454))
            let joined: SDF
            switch cell.row * 4 + cell.column {
            case 0: joined = a.columnsUnion(b, radius: 30, count: count)
            case 1: joined = a.columnsSubtract(b, radius: 30, count: count)
            case 2: joined = a.columnsIntersect(b, radius: 30, count: count)
            case 3: joined = a.pipe(b, radius: 16)
            case 4: joined = a.engrave(.circle(radius: 70).at(x: 8, y: 0), depth: 10)
            case 5: joined = a.groove(.circle(radius: 70).at(x: 8, y: 0), depth: 12, width: 10)
            case 6: joined = a.tongue(.circle(radius: 70).at(x: 8, y: 0), height: 12, width: 10)
            default:
                // The carpentry pair: a plank with a groove, and the ridged plank that
                // mates into it, parted so the fit reads.
                let seam = SDF.rect(width: 4, height: 220)
                let grooved = SDF.rect(width: 92, height: 190).at(x: -52, y: 0)
                    .groove(seam.at(x: -52 + 46, y: 0), depth: 16, width: 12)
                    .colored(Color(hex: 0x46c2ff))
                let tongued = SDF.rect(width: 92, height: 190).at(x: 56, y: 0)
                    .tongue(seam.at(x: 56 - 46, y: 0), height: 14, width: 10)
                    .colored(Color(hex: 0xffb454))
                joined = grooved.union(tongued)
            }
            withState {
                translate(cell.center)
                scale(0.92)
                stroke(Color(white: 0.85))
                strokeWeight(2)
                drawSDF(joined)
            }
            fill(Color(white: 0.55))
            textSize(16)
            textAlign(.center)
            drawText(labels[cell.row * 4 + cell.column],
                     at: Vector2(cell.center.x, cell.frame.bottomLeft.y - 6))
        }
    }
}
