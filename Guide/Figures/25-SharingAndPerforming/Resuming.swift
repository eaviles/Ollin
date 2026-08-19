// figure: frame=1
//
// Guide diagram (Chapter 25): what a checkpoint buys. The same wall either side
// of a quit: every tile it had is still where it was, and the piece carries on
// adding to it rather than starting the wall again.
import Ollin

final class Resuming: Sketch {
    override var canvasSize: CanvasSize { .size(880, 452) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.55)
    let accent = Color(hex: 0xE4572E)
    let board = Color(hex: 0x1A1A1E)

    let tint = Ramp([Color(hex: 0x354056), Color(hex: 0x6B9EC7), Color(hex: 0xF0CC85),
                     Color(hex: 0xDC7059)])

    /// The cells the first run filled, and the three the second run adds.
    let filled = [3, 9, 12, 18, 21, 26, 30, 33, 37, 41, 45, 52, 57, 60]
    let added = [7, 24, 49]

    override func draw() {
        background(paper)
        noStroke()

        wall(at: Vector2(60, 88), cells: filled, new: [],
             title: "running since Monday", note: "14 tiles down")
        wall(at: Vector2(520, 88), cells: filled, new: added,
             title: "quit, and run again", note: "the same 14, and three more")

        // The break between them.
        stroke(accent)
        strokeWeight(2)
        drawLine(Vector2(370, 223), Vector2(500, 223))
        noStroke()
        fill(accent)
        drawCircle(500, 223, 5)
        textSize(15)
        textAlign(.center, .bottom)
        drawText("relaunch", 435, 215)

        fill(soft)
        textSize(16)
        textAlign(.center, .top)
        drawText("the tiles are @Saved, so the wall is state rather than something the clock can rebuild",
                 width / 2, 408)
    }

    /// One 8-by-8 wall, with the tiles it kept and the tiles it gained.
    func wall(at origin: Vector2, cells: [Int], new: [Int], title: String, note: String) {
        let side = 270.0, columns = 8.0
        let cell = side / columns

        fill(ink)
        textSize(17)
        textAlign(.left, .bottom)
        drawText(title, origin.x, origin.y - 14)

        fill(board)
        drawRect(origin.x, origin.y, side, side, cornerRadius: 8)

        for (index, name) in (cells + new).enumerated() {
            let column = Double(name % 8), row = Double(name / 8)
            let middle = Vector2(origin.x + (column + 0.5) * cell,
                                 origin.y + (row + 0.5) * cell)
            let isNew = index >= cells.count
            fill(tint.color(at: Double(name % 7) / 6))
            drawRect(center: middle, width: cell * 0.74, height: cell * 0.74,
                     cornerRadius: cell * 0.2)
            if isNew {
                // The three the second run added, ringed so they read as new.
                noFill()
                stroke(accent)
                strokeWeight(2)
                drawRect(center: middle, width: cell * 0.94, height: cell * 0.94,
                         cornerRadius: cell * 0.26)
                noStroke()
            }
        }

        fill(soft)
        textSize(15)
        textAlign(.left, .top)
        drawText(note, origin.x, origin.y + side + 14)
    }
}
