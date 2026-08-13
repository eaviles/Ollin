// figure: frame=1
//
// Guide diagram (Chapter 22): what an extension package is. On the left, the
// package and the one file that matters in it. On the right, the sketch that
// imports it, and what the borrowed call draws.
//
// The spiral here is drawn by the same geometry the generated starter emits, so
// the picture on the right is genuinely what that code produces. The figure
// carries its own copy because a Guide figure cannot depend on a package that
// lives outside the repository.
import Foundation
import Ollin

final class ExtensionShape: Sketch {
    override var canvasSize: CanvasSize { .size(880, 460) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.55)
    let accent = Color(hex: 0xE4572E)
    let code = Color(hex: 0x0C0C10)

    override func draw() {
        background(paper)

        let left = Rectangle(x: 36, y: 70, width: 330, height: 300)
        let right = Rectangle(x: 514, y: 70, width: 330, height: 300)

        card(left, title: "ollinx-halftone", subtitle: "a package, published on its own")
        card(right, title: "MySketch.swift", subtitle: "somebody else's piece")

        // The package: the one file that carries the addition.
        textSize(12.5)
        textAlign(.left, .top)
        lines([
            "Sources/OllinxHalftone/",
            "",
            "extension Sketch {",
            "  func drawSpiral(center: Vector2,",
            "                  radius: Double) {",
            "    drawPolyline(points)",
            "  }",
            "}",
        ], in: left)

        // The sketch: two lines, and one of them is the import.
        lines([
            "import Ollin",
            "import OllinxHalftone",
            "",
            "drawSpiral(center: middle,",
            "           radius: 90)",
        ], in: right)

        // What the borrowed call draws, under the sketch that called it.
        withState {
            stroke(ink)
            strokeWeight(2)
            noFill()
            drawSpiral(center: Vector2(right.center.x, 300), radius: 55)
        }

        // The one thing that crosses between them.
        let gap = (left.x + left.width + right.x) / 2
        stroke(accent)
        strokeWeight(2)
        drawLine(Vector2(left.x + left.width + 10, 200), Vector2(right.x - 12, 200))
        noStroke()
        fill(accent)
        drawCircle(right.x - 12, 200, 4)
        fill(accent)
        textSize(14)
        textAlign(.center, .bottom)
        drawText("import", gap, 192)
        fill(soft)
        textSize(12)
        textAlign(.center, .top)
        drawText("nothing registers", gap, 210)

        fill(soft)
        textSize(18)
        textAlign(.center, .top)
        drawText("An extension is a package that depends on Ollin. There is no plug-in format.",
                 width / 2, 400)
    }

    /// A titled card, the two halves of the arrangement.
    func card(_ rect: Rectangle, title: String, subtitle: String) {
        noStroke()
        fill(Color(white: 1))
        drawRect(rect, cornerRadius: 12)
        stroke(Color(hex: 0x2B2B2B, alpha: 0.18))
        strokeWeight(1)
        noFill()
        drawRect(rect, cornerRadius: 12)

        noStroke()
        fill(ink)
        textSize(15)
        textAlign(.left, .top)
        drawText(title, rect.x + 18, rect.y + 14)
        fill(soft)
        textSize(12)
        drawText(subtitle, rect.x + 18, rect.y + 34)
    }

    /// A block of code inside a card, on its own dark strip.
    func lines(_ text: [String], in rect: Rectangle) {
        let top = rect.y + 62
        noStroke()
        fill(code)
        drawRect(rect.x + 14, top - 8, rect.width - 28, Double(text.count) * 17 + 16, cornerRadius: 8)

        textSize(12.5)
        textAlign(.left, .top)
        for (i, line) in text.enumerated() {
            fill(line.isEmpty ? code : Color(white: 0.94))
            drawText(line, rect.x + 26, top + Double(i) * 17)
        }
    }

    /// The starter's own geometry, so the picture is what that code draws.
    func drawSpiral(center: Vector2, radius: Double, turns: Double = 3, steps: Int = 240) {
        var points: [Vector2] = []
        for step in 0...steps {
            let along = Double(step) / Double(steps)
            let angle = along * turns * .tau
            points.append(center + Vector2(cos(angle), sin(angle)) * (along * radius))
        }
        drawPolyline(points)
    }
}
