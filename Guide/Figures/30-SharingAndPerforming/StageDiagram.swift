// figure: frame=200
//
// Guide diagram (Chapter 30): the performance host, annotated. A stylized
// OllinLiveCoding window drawn with Ollin itself: the sketch fills the stage,
// the code rides over it as translucent text, a toast confirms the last
// evaluation. Callouts name the moving parts.
import Ollin

final class StageDiagram: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.6)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(Color(hex: 0xF7F5F1))

        // The window: a dark stage with the piece letterboxed on it.
        let window = Rectangle(x: 230, y: 62, width: 420, height: 400)
        fill(Color(hex: 0x0C0C10))
        noStroke()
        drawRect(window, cornerRadius: 14)

        let stage = Rectangle(x: window.center.x - 150, y: window.y + 40,
                              width: 300, height: 300)
        let piece: Visual = .oscillator(frequency: 11, speed: 0.6, colorShift: 0.5)
            .kaleidoscope(5)
            .displaced(by: .noise(scale: 3, speed: 0.25), amount: 0.09)
            .posterized(bins: 6, gamma: 0.75)
        drawImage(generate(piece, width: 300, height: 300).image, in: stage)

        // The code, riding over the visuals on translucent strips.
        let lines = [
            "drawVisual(",
            "    .oscillator(frequency: 11, colorShift: 0.5)",
            "        .kaleidoscope(5)",
            "        .displaced(by: .noise(scale: 3),",
            "                   amount: 0.09)",
            "        .posterized(bins: 6, gamma: 0.75)",
            ")",
        ]
        textSize(14)
        textAlign(.left, .top)
        for (i, line) in lines.enumerated() {
            let y = window.y + 58 + Double(i) * 25
            let w = textWidth(line)
            noStroke()
            fill(Color(hex: 0x000000, alpha: 0.55))
            drawRect(window.x + 24, y - 3, w + 12, 23)
            fill(Color(white: 0.96))
            drawText(line, window.x + 30, y)
        }

        // The evaluated toast.
        fill(Color(hex: 0x1E3B26, alpha: 0.92))
        drawRect(window.x + window.width - 160, window.y + 16, 140, 28, cornerRadius: 8)
        fill(Color(hex: 0x8FE3A4))
        textSize(13)
        textAlign(.center, .center)
        drawText("Evaluated · 1.3 s", window.x + window.width - 90, window.y + 30)

        // Callouts.
        textSize(15)
        callout("the code rides on top,", "part of the show",
                at: Vector2(40, 120), to: Vector2(window.x + 26, 150), alignRight: false)
        callout("the piece fills the stage,", "letterboxed on black",
                at: Vector2(40, 330), to: Vector2(stage.x + 40, 360), alignRight: false)
        callout("⌘↩ evaluates the buffer;", "the clock carries across",
                at: Vector2(845, 110), to: Vector2(window.x + window.width - 30, 100), alignRight: true)
        callout("typos land in a strip;", "the show never stops",
                at: Vector2(845, 390), to: Vector2(window.x + window.width - 70, 448), alignRight: true)

        noStroke()
        fill(soft)
        textSize(19)
        textAlign(.center, .top)
        drawText("swift run OllinLiveCoding: the editor is inside the window, and the window is the show",
                 width / 2, 505)
    }

    func callout(_ line1: String, _ line2: String, at p: Vector2, to target: Vector2,
                 alignRight: Bool) {
        noStroke()
        fill(ink)
        textAlign(alignRight ? .right : .left, .top)
        drawText(line1, p.x, p.y)
        drawText(line2, p.x, p.y + 22)
        // Start the leader at the text edge facing the target, so it never
        // crosses its own words.
        let widest = max(textWidth(line1), textWidth(line2))
        let anchor = Vector2(alignRight ? p.x - widest - 10 : p.x + widest + 10, p.y + 22)
        stroke(accent)
        strokeWeight(2)
        drawLine(anchor, target)
        noStroke()
        fill(accent)
        drawCircle(target.x, target.y, 4)
    }
}
