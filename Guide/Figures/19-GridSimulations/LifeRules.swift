// figure: frame=0 probe
//
// Guide diagram (Chapter 19): Conway's rules. Three neighborhoods, three
// fates: a cell with two or three live neighbors survives, any other count
// kills it, and an empty cell with exactly three neighbors is born.
import Ollin

final class LifeRules: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.45)
    let alive = Color(hex: 0x1F8A70)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(Color(hex: 0xF7F5F1))

        // (center alive?, live neighbor cells, outcome alive?, caption)
        let cases: [(Bool, [(Int, Int)], Bool, String)] = [
            (true, [(-1, 0)], false, "1 neighbor: dies of loneliness"),
            (true, [(-1, 0), (1, 1), (0, -1)], true, "2 or 3: lives on"),
            (false, [(-1, 0), (1, 1), (0, -1)], true, "empty with exactly 3: born"),
        ]

        let cell = 46.0
        for (i, rule) in cases.enumerated() {
            let ox = 60 + Double(i) * 280
            panel(at: Vector2(ox, 90), cell: cell, centerAlive: rule.0, neighbors: rule.1)
            arrow(from: Vector2(ox + cell * 1.5 - 20, 90 + cell * 3 + 40),
                  to: Vector2(ox + cell * 1.5 - 20, 90 + cell * 3 + 80))
            // The outcome: the same center cell, next generation.
            noStroke()
            fill(rule.2 ? alive : Color(hex: 0xDDD8CC))
            drawRect(ox + cell, 90 + cell * 3 + 95, cell, cell)
            noFill()
            stroke(faint)
            strokeWeight(1.5)
            drawRect(ox + cell, 90 + cell * 3 + 95, cell, cell)
            noStroke()
            fill(faint)
            textSize(16)
            textAlign(.center, .top)
            drawText(rule.3, ox + cell * 1.5, 90 + cell * 3 + 155)
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("every cell counts its eight neighbors, all at once, every frame", width / 2, 498)
    }

    func panel(at origin: Vector2, cell: Double, centerAlive: Bool, neighbors: [(Int, Int)]) {
        for row in -1 ... 1 {
            for col in -1 ... 1 {
                let x = origin.x + Double(col + 1) * cell
                let y = origin.y + Double(row + 1) * cell
                let isCenter = row == 0 && col == 0
                let isAlive = neighbors.contains { $0.0 == col && $0.1 == row }
                    || (isCenter && centerAlive)
                noStroke()
                fill(isAlive ? alive : Color(hex: 0xEDE8DC))
                drawRect(x, y, cell, cell)
                noFill()
                stroke(isCenter ? accent : faint)
                strokeWeight(isCenter ? 3 : 1)
                drawRect(x, y, cell, cell)
            }
        }
    }

    func arrow(from a: Vector2, to b: Vector2) {
        let dir = (b - a).normalized
        stroke(accent)
        strokeWeight(3)
        drawLine(a, b - dir * 10)
        noStroke()
        fill(accent)
        drawPolygon([b, b - dir * 14 + dir.perpendicular * 6,
                        b - dir * 14 - dir.perpendicular * 6])
    }
}
