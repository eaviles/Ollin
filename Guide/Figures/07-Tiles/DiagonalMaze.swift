// figure: frame=0
//
// Guide diagram (Chapter 7): the maze of diagonals. One coin per cell on the
// left, and on the right the same diagonals joined end to end, each joined run
// in its own color, so what looks like loose marks reads as long paths.
import Ollin

final class DiagonalMaze: Sketch {
    override var canvasSize: CanvasSize { .size(880, 460) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)

    override func draw() {
        background(paper)
        seed(6)

        let left = Rectangle(x: 92, y: 60, width: 320, height: 320)
        let right = Rectangle(x: 468, y: 60, width: 320, height: 320)
        // One design, drawn twice: the same bits laid over both boxes, so the
        // right panel really is the left one joined up.
        let maze = tenPrint(in: left, columns: 16, rows: 16)
        let joined = TenPrint(grid: Grid(in: right, columns: 16, rows: 16), bits: maze.bits)

        noFill()
        strokeCap(.round)
        strokeWeight(5)
        stroke(ink)
        for line in maze.lines { drawPolyline(line.points) }

        for (index, run) in joined.runs.enumerated() {
            stroke(CosinePalette.rainbow.color(at: (Double(index) * 0.6180339887)
                .truncatingRemainder(dividingBy: 1)))
            drawPolyline(run.points)
        }

        frame(left, title: "one coin per cell")
        frame(right, title: "the same lines, joined into \(joined.runs.count) runs")

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("the diagonals meet at the corners, so the marks are already paths",
                 width / 2, 404)
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
        drawText(title, r.x, r.y - 20)
    }
}
