// figure: frame=1 themed
//
// Guide diagram (Chapter 17): one helper file, read by two shaders. On the left
// the helper and the single function in it. On the right the two shaders that
// name it, each calling that function with a different amount, and beside each
// one what that amount does to a plain grid.
//
// The two tiles are warped by the same arithmetic the code strip shows, so the
// pictures are what the printed function actually does rather than a drawing of
// the idea.
import Foundation
import Ollin
import OllinDiagram

final class SharedHelper: Sketch {
    override var canvasSize: CanvasSize { .size(880, 460) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.55) }
    var accent: Color { theme.accent }
    let code = Color(hex: 0x0C0C10)

    override func draw() {
        background(paper)

        let helper = Rectangle(x: 36, y: 96, width: 320, height: 228)
        card(helper, title: "helpers.metal", subtitle: "written once")
        lines([
            "float2 swirl(float2 uv,",
            "             float amount) {",
            "  float2 p = uv - 0.5;",
            "  float a = amount * length(p);",
            "  float s = sin(a), c = cos(a);",
            "  return float2(p.x * c - p.y * s,",
            "                p.x * s + p.y * c)",
            "         + 0.5;",
            "}",
        ], in: helper)

        let shaders = [
            (rect: Rectangle(x: 452, y: 62, width: 250, height: 138), amount: 2.2,
             name: "Ripple.metal", call: "swirl(uv, 2.2)"),
            (rect: Rectangle(x: 452, y: 224, width: 250, height: 138), amount: 5.5,
             name: "Grain.metal", call: "swirl(uv, 5.5)"),
        ]

        for shader in shaders {
            card(shader.rect, title: shader.name, subtitle: "reads it by name")
            lines(["#include \"helpers.metal\"",
                   "",
                   "return sample(info,",
                   "       \(shader.call));"],
                  in: shader.rect, highlightFirst: true)
            tile(Rectangle(x: 730, y: shader.rect.y + 18, width: 108, height: 102),
                 amount: shader.amount)
        }

        // The one thing that crosses: the name in the include line.
        stroke(accent)
        strokeWeight(2)
        noFill()
        for shader in shaders {
            let from = Vector2(helper.x + helper.width + 10, helper.center.y)
            let to = Vector2(shader.rect.x - 12, shader.rect.y + 96)
            drawBezier(from, Vector2((from.x + to.x) / 2, to.y), to)
            noStroke()
            fill(accent)
            drawCircle(to.x, to.y, 4)
            stroke(accent)
            strokeWeight(2)
            noFill()
        }

        noStroke()
        fill(soft)
        textSize(18)
        textAlign(.center, .top)
        drawText("A file is read once, however many shaders name it.", width / 2, 396)
    }

    /// A titled card.
    func card(_ rect: Rectangle, title: String, subtitle: String) {
        noStroke()
        fill(darkTheme ? Color(hex: 0x2A2724) : Color(white: 1))
        drawRect(rect, cornerRadius: 12)
        stroke(theme.ink(0.18))
        strokeWeight(1)
        noFill()
        drawRect(rect, cornerRadius: 12)

        noStroke()
        fill(ink)
        textSize(15)
        textAlign(.left, .top)
        drawText(title, rect.x + 18, rect.y + 12)
        fill(soft)
        textSize(12)
        drawText(subtitle, rect.x + 18, rect.y + 32)
    }

    /// A block of code inside a card, on its own dark strip. The first line can be
    /// picked out, which is where the include sits.
    func lines(_ text: [String], in rect: Rectangle, highlightFirst: Bool = false) {
        let top = rect.y + 58
        noStroke()
        fill(code)
        drawRect(rect.x + 14, top - 8, rect.width - 28, Double(text.count) * 17 + 16, cornerRadius: 8)

        textSize(12.5)
        textAlign(.left, .top)
        for (i, line) in text.enumerated() {
            let picked = highlightFirst && i == 0
            fill(line.isEmpty ? code : (picked ? accent : Color(white: 0.94)))
            drawText(line, rect.x + 26, top + Double(i) * 17)
        }
    }

    /// A plain grid put through the printed function, so the tile shows what that
    /// amount does rather than standing in for it.
    func tile(_ rect: Rectangle, amount: Double) {
        noStroke()
        fill(theme.ink(0.05))
        drawRect(rect, cornerRadius: 8)
        stroke(theme.ink(0.16))
        strokeWeight(1)
        noFill()
        drawRect(rect, cornerRadius: 8)

        stroke(ink)
        strokeWeight(1.2)
        noFill()
        let rows = 8, steps = 48
        for row in 0...rows {
            let v = Double(row) / Double(rows)
            var points: [Vector2] = []
            for step in 0...steps {
                let u = Double(step) / Double(steps)
                let warped = swirl(Vector2(u, v), amount: amount)
                points.append(Vector2(rect.x + warped.x * rect.width,
                                      rect.y + warped.y * rect.height))
            }
            drawPolyline(points)
        }
    }

    /// The same arithmetic the code strip prints.
    func swirl(_ uv: Vector2, amount: Double) -> Vector2 {
        let p = uv - Vector2(0.5, 0.5)
        let a = amount * p.length
        return Vector2(p.x * cos(a) - p.y * sin(a), p.x * sin(a) + p.y * cos(a)) + Vector2(0.5, 0.5)
    }
}
