// figure: frame=140 themed
//
// Guide diagram (Chapter 16): what the feedback transform does. The same
// orbiting dot draws into four feedback layers; each panel transforms its
// past differently before drawing it back.
import Ollin

final class FeedbackSteps: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }

    var panels: [Feedback] = []

    override func setup() {
        panels = (0 ..< 4).map { _ in feedback(scale: 0.5) }
    }

    override func draw() {
        background(paper)

        // Per-panel transform of the past: fade only, zoom, rotate, both.
        let setups: [(String, (Sketch) -> Void)] = [
            ("fade only", { _ in }),
            ("fade + zoom", { s in s.scale(1.02) }),
            ("fade + rotate", { s in s.rotate(0.05) }),
            ("fade + zoom + rotate", { s in s.scale(0.985); s.rotate(0.045) }),
        ]

        let t = Double(frameCount) * 0.045
        let orbit = Vector2(width / 2 + cos(t) * 190, height / 2 + sin(t * 1.3) * 140)

        for (i, panel) in panels.enumerated() {
            withFeedback(panel) { prev in
                background(Color(hex: 0x10141D))
                withState {
                    translate(width / 2, height / 2)
                    setups[i].1(self)
                    translate(-width / 2, -height / 2)
                    tint(Color(white: 1, alpha: 0.94))
                    drawImage(prev, 0, 0)
                    noTint()
                }
                noStroke()
                fill(Color(hex: 0xFFC94A))
                drawCircle(center: orbit, radius: 14)
            }
        }

        // Lay the four results out as panels, each labeled inside.
        let w = 424.0, h = 265.0
        for (i, panel) in panels.enumerated() {
            let x = 10 + Double(i % 2) * (w + 12)
            let y = 10 + Double(i / 2) * (h + 10)
            drawImage(panel.image, in: Rectangle(x: x, y: y, width: w, height: h))
            noStroke()
            fill(Color(white: 1, alpha: 0.75))
            textSize(16)
            textAlign(.left, .bottom)
            drawText(setups[i].0, x + 12, y + h - 10)
        }
    }
}
