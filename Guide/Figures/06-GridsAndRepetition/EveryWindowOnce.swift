// figure: frame=0 themed
//
// Guide diagram (Chapter 6): a de Bruijn sequence. On the left the eight-bead
// ring for two symbols and a window of three, with the eight windows it holds
// listed under it. On the right the sixty-four bead ring for four symbols, with
// one window picked out.
import Ollin

final class EveryWindowOnce: Sketch {
    override var canvasSize: CanvasSize { .size(880, 460) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    let accent = Color(hex: 0xE07A5F)
    var note: Color { darkTheme ? Color(hex: 0xE8E5E1, alpha: 0.62) : Color(hex: 0x6E6A63) }

    override func draw() {
        background(paper)

        let run = deBruijnSequence(symbols: 2, window: 3)
        let cell = 34.0
        let left = Vector2(64, 74)

        // The run itself, read as a ring: the last two beads are drawn again, pale,
        // to show where the windows at the end wrap round to.
        for (index, symbol) in run.enumerated() {
            bead(at: Vector2(left.x + Double(index) * cell, left.y), size: cell, on: symbol == 1)
        }
        for offset in 0 ..< 2 {
            let symbol = run[offset]
            bead(at: Vector2(left.x + Double(run.count + offset) * cell, left.y),
                 size: cell, on: symbol == 1, faded: true)
        }

        // Every window of three, read from that ring, one under the other.
        let small = 17.0
        for start in run.indices {
            let y = left.y + 62 + Double(start) * (small + 7)
            noStroke()
            fill(note)
            textSize(13)
            textAlign(.right, .middle)
            drawText("\(start)", left.x - 10, y + small / 2)
            for step in 0 ..< 3 {
                let symbol = run[(start + step) % run.count]
                bead(at: Vector2(left.x + Double(step) * small, y), size: small, on: symbol == 1)
            }
        }

        noStroke()
        fill(ink)
        textSize(17)
        textAlign(.left, .middle)
        drawText("eight beads, and the eight windows they hold", left.x - 26, left.y + 268)
        fill(note)
        textSize(15)
        drawText("no two alike, and none missing", left.x - 26, left.y + 292)

        ring(center: Vector2(650, 200), radius: 118)

        fill(ink)
        noStroke()
        textSize(21)
        textAlign(.center, .top)
        drawText("every window appears once, so a glimpse says where you are",
                 width / 2, 404)
    }

    func bead(at corner: Vector2, size: Double, on: Bool, faded: Bool = false) {
        let alpha = faded ? 0.3 : 1.0
        fill(on ? accent.withAlpha(alpha) : Color(white: 0.87).withAlpha(alpha))
        stroke(ink.withAlpha(faded ? 0.2 : 0.65))
        strokeWeight(1.5)
        drawRect(Rectangle(x: corner.x, y: corner.y, width: size - 3, height: size - 3))
    }

    /// The four-symbol ring, with one window of three picked out.
    func ring(center: Vector2, radius: Double) {
        let code = DeBruijnCode(symbols: 4, window: 3)
        let beads = code.sequence.count
        let step = Double.tau / Double(beads)
        let at = 11
        noFill()
        strokeCap(.butt)
        for (index, symbol) in code.sequence.enumerated() {
            let start = Double(index) * step - .pi / 2
            let picked = (0 ..< code.window).contains { (at + $0) % beads == index }
            let tone = Color(white: 0.82 - Double(symbol) * 0.17)
            stroke(picked ? accent : tone)
            strokeWeight(picked ? 26 : 15)
            drawArc(center: center, rx: radius, ry: radius,
                    start: start + step * 0.1, stop: start + step * 0.9)
        }
        noStroke()
        fill(ink)
        textSize(17)
        textAlign(.center, .middle)
        drawText("bead \(code.position(of: code.window(at: at)) ?? -1)", at: center)
        fill(note)
        textSize(14)
        drawText("of \(beads), four colors", at: center + Vector2(0, 24))
    }
}
