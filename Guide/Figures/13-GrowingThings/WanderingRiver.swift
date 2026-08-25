// figure: frame=0 themed
//
// Guide diagram (Chapter 13): the meandering river. Left, the rule: the
// outside of a bend is eaten away and the whole bend slides downstream,
// pushed by the water that entered it upstream. Right, what that does after
// two thousand steps: a wandering channel over the ribbons of everywhere it
// used to run, with a cut-off loop left beside it as a crescent lake.
import Ollin
import OllinDiagram

final class WanderingRiver: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.4) }
    var soft: Color { theme.ink(0.12) }
    var accent: Color { theme.accent }
    let water = Color(hex: 0x2C4A6E)
    let waterPale = Color(hex: 0x7FA8C9)
    let scarInks = [Color(hex: 0xC26D3F), Color(hex: 0x8A9B68),
                    Color(hex: 0xC7A94F), Color(hex: 0x71486E)]

    var river: Meander!

    override func setup() {
        river = Meander.line(from: Vector2(-300, 180), to: Vector2(430, 160),
                             seed: 13, width: 8, recordEvery: 40)
        river.oxbowShrink = 0.001
        river.step(2800)
    }

    func panel(_ i: Int) -> Rectangle {
        Rectangle(x: 50 + Double(i) * 420, y: 60, width: 370, height: 340)
    }

    override func draw() {
        background(paper)
        textSize(17)

        // Left: the rule.
        let left = panel(0)
        frame(left, title: "a bend eats its outside bank")
        let bend = (0 ... 60).map { i -> Vector2 in
            let t = Double(i) / 60
            return Vector2(left.x + 20 + t * 330,
                           left.y + 170 - 70 * sin(t * 2 * .pi))
        }
        noFill()
        stroke(waterPale)
        strokeWeight(14)
        drawPolyline(bend)
        stroke(water)
        strokeWeight(3)
        drawPolyline(bend)
        // The outside of the top bend, eaten away.
        let apex = Vector2(left.x + 102, left.y + 100)
        arrow(from: apex + Vector2(0, -14), to: apex + Vector2(0, -52))
        label("the outside is eaten away", apex + Vector2(30, -66), color: accent)
        // The whole train, sliding downstream.
        let low = Vector2(left.x + 267, left.y + 240)
        arrow(from: low + Vector2(-30, 24), to: low + Vector2(36, 24))
        label("and the bend slides downstream", low + Vector2(0, 48), color: accent)

        // Right: what that builds.
        let right = panel(1)
        frame(right, title: "twenty-eight hundred steps later")
        withClip(right) {
            withState {
                translate(right.x, right.y)
                noFill()
                strokeWeight(river.width * 0.7)
                for (index, scar) in river.scars.enumerated() {
                    let recency = Double(index + 1) / Double(river.scars.count)
                    stroke(scarInks[index % scarInks.count]
                        .withAlpha(0.08 + 0.2 * recency))
                    drawPolyline(scar)
                }
                stroke(waterPale.withAlpha(0.8))
                strokeWeight(river.width * 0.8)
                for oxbow in river.oxbows {
                    drawPolyline(oxbow.points)
                }
                stroke(water)
                strokeWeight(river.width)
                drawPolyline(river.centerline)
            }
        }

        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("the river turns hardest where the water arrived already turning",
                 width / 2, 428)
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textAlign(.left, .middle)
        drawText(title, r.x + 2, r.y - 20)
    }

    func label(_ text: String, _ at: Vector2, color: Color? = nil) {
        noStroke()
        fill(color ?? faint)
        textAlign(.center, .middle)
        drawText(text, at: at)
    }

    func arrow(from: Vector2, to: Vector2) {
        stroke(accent)
        strokeWeight(2.5)
        drawLine(from, to)
        let dir = (to - from) * (1 / Swift.max((to - from).length, 1e-9))
        let side = Vector2(-dir.y, dir.x)
        drawLine(to, to - dir * 9 + side * 5)
        drawLine(to, to - dir * 9 - side * 5)
    }
}
