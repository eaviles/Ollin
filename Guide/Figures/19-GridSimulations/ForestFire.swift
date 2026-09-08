// figure: frame=900 themed
//
// Guide diagram (Chapter 19): the Drossel-Schwabl forest fire. On the left the
// whole rule as three states and the moves between them; on the right a field
// running it, nine hundred steps in, in the same three colors. Nothing in the
// rule names a density, and the one on the right is what it settles at.
import Ollin
import OllinDiagram

final class ForestFireFigure: Sketch {
    override var canvasSize: CanvasSize { .size(880, 430) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.4) }
    var soft: Color { theme.ink(0.6) }
    var accent: Color { theme.accent }

    /// The field's own three colors, which the boxes wear so the rule and the
    /// picture read as one thing.
    private let bare = Color(hex: 0x17120E)
    private let tree = Color(hex: 0x2F7D45)
    private let fire = Color(hex: 0xFFC24A)

    private var forest: SimField!
    private lazy var woods = Ramp(stops: [(0.0, bare), (0.5, tree), (1.0, fire)])

    override func setup() {
        // A field is the canvas's own shape, so the panel below is drawn at the
        // field's aspect (two cells to a side) rather than squeezed into a square.
        forest = makeSimField(.forestFire(growth: 0.02, lightning: 0.00004, seed: 5),
                              scale: 190.0 / width)
    }

    override func draw() {
        background(paper)

        state(y: 46, fillColor: bare, title: "bare ground", light: true)
        state(y: 176, fillColor: tree, title: "a tree", light: false)
        state(y: 306, fillColor: fire, title: "burning", light: true)

        arrow(from: Vector2(190, 122), to: Vector2(190, 170))
        arrow(from: Vector2(190, 252), to: Vector2(190, 300))
        label("it grows, with a small chance each step", at: Vector2(208, 132))
        label("a neighbor is alight, or lightning strikes", at: Vector2(208, 262))

        // The way back: burning is bare ground again on the very next step.
        stroke(accent)
        strokeWeight(3)
        noFill()
        drawPolyline([Vector2(78, 344), Vector2(52, 344), Vector2(52, 84), Vector2(64, 84)])
        arrow(from: Vector2(58, 84), to: Vector2(78, 84))
        withState {
            translate(Vector2(40, 214))
            rotate(-.pi / 2)
            noStroke()
            fill(soft)
            textSize(14)
            textAlign(.center)
            drawText("always, the next step", 0, 0)
        }

        drawImage(forest.filtered(.gradientMap(woods)).image, 520, 130, 340, 170)
        noStroke()
        fill(soft)
        textSize(13)
        textAlign(.center)
        drawText("one field, 900 steps in", 690, 326)
    }

    // MARK: Pieces

    private func state(y: Double, fillColor: Color, title: String, light: Bool) {
        fill(fillColor)
        stroke(faint)
        strokeWeight(1.5)
        drawRect(80, y, 220, 76, cornerRadius: 10)
        noStroke()
        fill(light ? Color(white: 0.94) : Color(white: 0.97))
        textSize(19)
        textAlign(.center)
        drawText(title, 190, y + 45)
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
