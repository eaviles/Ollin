// figure: frame=0
//
// Guide diagram (Chapter 16): the two CPU cellular automata. Left, elementary
// rule 30 grown downward from a single live cell, one row per generation.
// Right, Langton's ant after a hundred thousand steps, the chaotic blot it
// paints first and the diagonal highway it eventually escapes along.
import Ollin

final class WolframAndTurmite: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.18)

    let left = Rectangle(x: 84, y: 70, width: 320, height: 320)
    let right = Rectangle(x: 476, y: 70, width: 320, height: 320)

    let ant = Turmite(.langton, columns: 260, rows: 260)

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        noStroke()

        // Elementary rule 30: 161 generations from one live cell in the middle.
        let steps = 161
        let rows = elementaryCA(rule: 30, width: steps, generations: steps)
        let cellA = left.width / Double(steps)
        fill(ink)
        for (r, row) in rows.enumerated() {
            for (c, on) in row.enumerated() where on {
                drawRect(left.x + Double(c) * cellA, left.y + Double(r) * cellA,
                         cellA, cellA)
            }
        }

        // Langton's ant: chaos first, then the highway out of the corner.
        ant.step(100_000)
        let cellB = right.width / 260.0
        fill(ink)
        for painted in ant.paintedCells {
            drawRect(right.x + Double(painted.column) * cellB,
                     right.y + Double(painted.row) * cellB, cellB, cellB)
        }

        frame(left, title: "rule 30, one cell at a time")
        frame(right, title: "Langton's ant, 100,000 steps")

        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("tiny rules, run long enough", width / 2, 440)
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textSize(17)
        textAlign(.left, .middle)
        drawText(title, r.x + 2, r.y - 20)
    }
}
