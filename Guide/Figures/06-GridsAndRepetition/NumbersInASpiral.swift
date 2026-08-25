// figure: frame=0 themed
//
// Guide diagram (Chapter 6): the square spiral as a way of walking a grid. On
// the left the walk itself with the numbers it writes, on the right the same
// walk over a much larger square with only the primes marked, so the diagonals
// the marks fall on are visible.
import Ollin
import OllinDiagram

final class NumbersInASpiral: Sketch {
    override var canvasSize: CanvasSize { .size(880, 460) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }

    override func draw() {
        background(paper)

        let left = Rectangle(x: 92, y: 60, width: 320, height: 320)
        let right = Rectangle(x: 468, y: 60, width: 320, height: 320)

        // The walk, small enough to read every number it writes.
        let small = ulamSpiral(in: left, size: 7)
        noFill()
        stroke(Color(hex: 0xE07A5F, alpha: 0.55))
        strokeWeight(3)
        drawPolyline(small.path.points)

        noStroke()
        textSize(17)
        textAlign(.center, .middle)
        for (cell, number) in zip(small.grid.cells, small.numbers) {
            fill(isPrime(number) ? ink : Color(hex: 0x9A968E))
            drawText("\(number)", at: cell.center)
        }

        // The same walk, far enough out that the marks show their pattern.
        let big = ulamSpiral(in: right, size: 61)
        fill(ink)
        for point in big.primePoints {
            drawCircle(center: point, radius: big.grid.cellWidth * 0.34)
        }

        frame(left, title: "the walk, and what it writes")
        frame(right, title: "the primes of the first 3721 numbers")

        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("a test on the numbers becomes a picture, and the picture has lines in it",
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
