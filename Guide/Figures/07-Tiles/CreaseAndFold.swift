// figure: frame=0 themed
//
// Guide figure (Chapter 7): crease patterns. The flat Miura sheet with its
// mountains and valleys marked, the same sheet folded most of the way, and a
// rotating-squares cut sheet pulled half open.
import Ollin

final class CreaseAndFold: Sketch {
    override var canvasSize: CanvasSize { .size(880, 386) }

    @Param var darkTheme = false

    var canvasPaper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    let paper = Color(hex: 0x1A1410)
    let chalk = Color(hex: 0xF3E7D3)
    let warm = Color(hex: 0xE0724A)
    let cool = Color(hex: 0x5A8FC7)

    override func draw() {
        background(canvasPaper)

        let tile = 268.0, gap = 12.0
        let left = (width - tile * 3 - gap * 2) / 2
        let sheet = MiuraFold(columns: 4, rows: 5, major: 1, minor: 0.8,
                              angle: .pi / 3, fold: 0.46)

        for index in 0 ..< 3 {
            let frame = Rectangle(x: left + Double(index) * (tile + gap), y: 20,
                                  width: tile, height: tile)
            noStroke()
            fill(paper)
            drawRect(frame)

            switch index {
            case 0: drawPattern(sheet, in: frame.inset(by: 26))
            case 1: drawFolded(sheet, in: frame.inset(by: 18))
            default: drawCutSheet(in: frame.inset(by: 22))
            }

            noStroke()
            fill(Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.62))
            textFont(.system)
            textSize(16)
            textAlign(.center, .top)
            let labels = ["the pattern: mountains and valleys",
                          "the same sheet, folded",
                          "cut instead: squares that turn"]
            drawText(labels[index], frame.x + frame.width / 2, frame.y + frame.height + 8)
        }
    }

    private func drawPattern(_ sheet: MiuraFold, in frame: Rectangle) {
        let pattern = sheet.pattern.fitted(in: frame)
        noFill()
        strokeCap(.round)
        strokeWeight(3)
        stroke(chalk.withAlpha(0.30))
        drawCreases(pattern, .boundary)
        stroke(warm)
        drawCreases(pattern, .mountain)
        stroke(cool)
        drawCreases(pattern, .valley)
    }

    private func drawFolded(_ sheet: MiuraFold, in frame: Rectangle) {
        let panels = sheet.facets
        let lean = cos(Double.pi / 6), rise = sin(Double.pi / 6)
        let placed = fitted(panels.flatMap { panel in
            panel.map { Vector2(($0.x - $0.y) * lean, ($0.x + $0.y) * rise - $0.z) }
        }, in: frame)
        let light = Vector3(-0.35, -0.55, 0.76).normalized

        strokeWeight(1)
        for index in panels.indices.sorted(by: {
            panels[$0].reduce(0) { $0 + $1.x + $1.y } < panels[$1].reduce(0) { $0 + $1.x + $1.y }
        }) {
            let corners = Array(placed[(index * 4) ..< (index * 4 + 4)])
            let normal = (panels[index][1] - panels[index][0])
                .cross(panels[index][3] - panels[index][0]).normalized
            fill(Color.mix(Color(hex: 0x3A4258), chalk, t: 0.30 + abs(normal.dot(light)) * 0.66))
            stroke(paper.withAlpha(0.6))
            drawPolygon(corners)
        }
    }

    private func drawCutSheet(in frame: Rectangle) {
        let lattice = RotatingSquares(columns: 5, rows: 5, side: 1, ligament: 0.1, opening: 0.5)
        var widest = lattice
        widest.opening = 1
        let box = widest.bounds
        let scale = min(frame.width / box.width, frame.height / box.height)
        noStroke()
        for (index, square) in lattice.squares.enumerated() {
            let along = Double(index) / Double(lattice.squares.count - 1)
            fill(Color.mix(chalk, warm, t: along * 0.8))
            drawPolygon(square.points.map {
                Vector2(frame.center.x + ($0.x - box.center.x) * scale,
                        frame.center.y + ($0.y - box.center.y) * scale)
            })
        }
    }
}
