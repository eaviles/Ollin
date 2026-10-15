// figure: frame=150 themed
//
// Guide diagram (Chapter 11): soft bodies from outlines. The letters of a
// word, a star, and a lumpy blob, each one `addSoftBody(from:)` call, dropped
// into a box. They land, squash against the floor and each other, keep
// their area, and spring back toward their own shapes; the O keeps its
// counter.
import Ollin
import OllinDiagram
import OllinPhysics

final class SoftShapes: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    let face = OutlineFont(name: "AvenirNext-Heavy") ?? .systemBold
    let panel = Rectangle(x: 50, y: 40, width: 780, height: 420)

    var world = World()
    var letters: [SoftBody] = []
    var others: [SoftBody] = []

    override func setup() throws {
        world = World()
        letters = []
        others = []
        world.gravity = Vector2(0, 2000)
        world.bounds = panel

        textFont(face)
        textAlign(.center, .middle)
        textSize(170)
        for glyph in textToShapes("SOFT", panel.center.x, panel.y + 190) {
            letters.append(try world.addSoftBody(from: glyph, spacing: 5))
        }
        textFont(.system)

        let star = Shape((0 ..< 10).map { k in
            Vector2(panel.x + 90, panel.y + 90)
                + Vector2(angle: Double(k) / 10 * .tau - .pi / 2,
                          length: k.isMultiple(of: 2) ? 62 : 27)
        })
        others.append(try world.addSoftBody(from: star, spacing: 5))
        let blob = Shape((0 ..< 48).map { i in
            let turn = Double(i) / 48
            let wobble = 1 + 0.12 * sin(turn * .tau * 3) + 0.06 * cos(turn * .tau * 5)
            return Vector2(panel.x + panel.width - 80, panel.y + 70)
                + Vector2(angle: turn * .tau, length: 52 * wobble)
        })
        others.append(try world.addSoftBody(from: blob, spacing: 5))
    }

    override func draw() {
        background(theme.paper)
        world.advance(by: deltaTime)

        noFill()
        stroke(theme.ink(0.12))
        strokeWeight(2)
        drawRect(panel)

        strokeWeight(2)
        stroke(theme.ink)
        fill(theme.accent)
        for body in letters { drawShape(body.shape) }
        fill(theme.ink(0.14))
        for body in others { drawShape(body.shape) }

        noStroke()
        fill(theme.ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("one call per outline: each keeps its area and springs back to its shape",
                 width / 2, 490)
    }
}
