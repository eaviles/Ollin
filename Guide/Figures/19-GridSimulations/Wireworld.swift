// figure: frame=140 themed
//
// Guide diagram (Chapter 19): Wireworld. On the left the whole rule as four
// states and the moves between them; on the right a circuit running it, typed
// as text, a hundred and forty steps in: two ring clocks of different periods
// feeding one bus through diodes, with two lamps at its end.
import Ollin
import OllinDiagram

final class WireworldFigure: Sketch {
    override var canvasSize: CanvasSize { .size(940, 430) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.4) }
    var soft: Color { theme.ink(0.6) }
    var accent: Color { theme.accent }

    /// The field's own four colors, which the boxes wear so the rule and the
    /// picture read as one thing: the classic yellow wire, blue head, red tail.
    private let empty = Color(hex: 0x0B0B0F)
    private let wire = Color(hex: 0xE8B923)
    private let head = Color(hex: 0x2E7BFF)
    private let tail = Color(hex: 0xE0432E)

    /// The circuit, one character per cell: `#` wire, `H` a head, `t` its tail.
    private let circuit = [
        "..#tH######.....................................................",
        "..#.......#.......##............................................",
        "..#.......#########.######......................................",
        "..#.......#.......##.....#......................................",
        "..#########..............#..................................##..",
        ".........................#..................................##..",
        ".........................#.................................#....",
        ".........................##################################.....",
        ".........................#.................................#....",
        ".........................#..................................##..",
        "..#tH########............#..................................##..",
        "..#.........#.....##.....#......................................",
        "..#.........#######.######......................................",
        "..#.........#.....##............................................",
        "..#.........#...................................................",
        "..#.........#...................................................",
        "..###########...................................................",
    ]
    private let levels: [Character: WireworldCell] = [".": .empty, "#": .conductor,
                                                      "t": .tail, "H": .head]

    /// The field is 72 cells across the whole canvas, which puts the circuit's
    /// 64 columns into the panel on the right at a size you can read.
    private let cellsAcross = 72.0
    private var board: SimField!
    private lazy var colors = Ramp(stops: [(0.0, empty), (1.0 / 3.0, wire),
                                           (2.0 / 3.0, tail), (1.0, head)])

    override func setup() {
        board = makeSimField(.wireworld(), scale: cellsAcross / width)
    }

    override func draw() {
        background(paper)

        state(y: 26, fillColor: empty, title: "empty", light: true)
        state(y: 122, fillColor: wire, title: "wire", light: false)
        state(y: 218, fillColor: head, title: "electron head", light: true)
        state(y: 314, fillColor: tail, title: "electron tail", light: true)

        arrow(from: Vector2(190, 186), to: Vector2(190, 212))
        arrow(from: Vector2(190, 282), to: Vector2(190, 308))
        label("one or two neighbors are heads", at: Vector2(208, 194))
        label("always, the next step", at: Vector2(208, 290))
        label("nothing ever happens here", at: Vector2(208, 98), color: soft)

        // The way back: a tail is wire again on the very next step.
        stroke(accent)
        strokeWeight(3)
        noFill()
        drawPolyline([Vector2(78, 346), Vector2(52, 346), Vector2(52, 154), Vector2(64, 154)])
        arrow(from: Vector2(58, 154), to: Vector2(78, 154))
        withState {
            translate(Vector2(40, 250))
            rotate(-.pi / 2)
            noStroke()
            fill(soft)
            textSize(14)
            textAlign(.center)
            drawText("always, the next step", 0, 0)
        }

        withField(board) {
            noStroke()
            if frameCount == 1 {
                // The circuit sits in the field's own texel grid, which spans the
                // whole canvas; the panel on the right shows that part of it.
                let cell = width / cellsAcross
                for (y, row) in circuit.enumerated() {
                    for (x, ch) in row.enumerated() where ch != "." {
                        fill(levels[ch]!.color)
                        drawRect(Double(x + 4) * cell, Double(y + 8) * cell, cell, cell)
                    }
                }
            }
        }
        let cell = width / cellsAcross
        let panel = Rectangle(x: 3 * cell, y: 7 * cell, width: 66 * cell, height: 19 * cell)
        withClip(Rectangle(x: 470, y: 118, width: 440, height: 200)) {
            // The field, mapped so the circuit's part of it fills the panel.
            let scale = 440 / panel.width
            drawImage(board.filtered(.gradientMap(colors)).image,
                      470 - panel.x * scale, 118 - panel.y * scale, width * scale, height * scale)
        }
        noStroke()
        fill(soft)
        textSize(13)
        textAlign(.center)
        drawText("a circuit typed as text, 140 steps in", 690, 342)
    }

    // MARK: Pieces

    private func state(y: Double, fillColor: Color, title: String, light: Bool) {
        fill(fillColor)
        stroke(faint)
        strokeWeight(1.5)
        drawRect(80, y, 220, 64, cornerRadius: 10)
        noStroke()
        fill(light ? Color(white: 0.94) : Color(white: 0.12))
        textSize(19)
        textAlign(.center)
        drawText(title, 190, y + 39)
    }

    private func label(_ text: String, at position: Vector2, color: Color? = nil) {
        noStroke()
        fill(color ?? ink)
        textSize(13)
        textAlign(.left)
        drawText(text, position.x, position.y)
    }

    private func arrow(from a: Vector2, to b: Vector2) {
        let dir = (b - a).normalized
        stroke(accent)
        strokeWeight(3)
        drawLine(a, b - dir * 10)
        noStroke()
        fill(accent)
        drawPolygon([b, b - dir * 13 + dir.perpendicular * 5.5,
                        b - dir * 13 - dir.perpendicular * 5.5])
    }
}
