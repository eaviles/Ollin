// figure: frame=1
//
// Guide diagram (Chapter 31): one canvas, three displays. The canvas is drawn
// once, at the top, and each display below carries the part of it that its own
// place in the arrangement covers. The piece is the same picture in both rows,
// so the reader can see that the three panes are one thing cut in three rather
// than three pictures in a row.
import Ollin

final class ManyDisplays: Sketch {
    override var canvasSize: CanvasSize { .size(880, 620) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.55)
    let rule = Color(hex: 0x2B2B2B, alpha: 0.18)
    let accent = Color(hex: 0xE4572E)

    /// The canvas as one long picture, before anybody divides it.
    let canvas = Rectangle(x: 56, y: 92, width: 768, height: 168)

    /// The three displays, side by side with the gap a desk has between them.
    var displays: [Rectangle] {
        let gap = 18.0
        let width = (canvas.width - gap * 2) / 3
        return (0..<3).map {
            Rectangle(x: canvas.x + (width + gap) * Double($0), y: 396,
                      width: width, height: 148)
        }
    }

    override func draw() {
        background(paper)

        textSize(20)
        textAlign(.left, .top)
        fill(ink)
        drawText("one canvas, three displays", 56, 40)

        // The canvas: the whole picture, drawn once.
        piece(in: canvas, from: 0, to: 1)
        noFill()
        stroke(rule)
        strokeWeight(1)
        drawRect(corner: Vector2(canvas.x, canvas.y), width: canvas.width, height: canvas.height)

        // Where the divisions fall, and what each part is called.
        stroke(Color(hex: 0xF7F5F1, alpha: 0.7))
        strokeWeight(1.5)
        for cut in 1...2 {
            let x = canvas.x + canvas.width * Double(cut) / 3
            drawLine(x, canvas.y, x, canvas.y + canvas.height)
        }
        noStroke()
        fill(soft)
        textSize(13)
        textAlign(.center, .top)
        for part in 0..<3 {
            let middle = canvas.x + canvas.width * (Double(part) + 0.5) / 3
            drawText("shows \(part == 0 ? "0" : part == 1 ? "0.33" : "0.66") to "
                     + "\(part == 0 ? "0.33" : part == 1 ? "0.66" : "1")",
                     middle, canvas.y + canvas.height + 10)
        }
        textAlign(.right, .top)
        drawText("the canvas", canvas.x + canvas.width, canvas.y - 24)

        // One arrow per display, from its part of the canvas down to the pane
        // that carries it.
        stroke(accent)
        strokeWeight(1.5)
        for (part, display) in displays.enumerated() {
            let from = canvas.x + canvas.width * (Double(part) + 0.5) / 3
            let to = display.center.x
            drawLine(from, canvas.y + canvas.height + 34, from, 356)
            drawLine(from, 356, to, 356)
            drawLine(to, 356, to, display.y - 22)
            drawLine(to - 5, display.y - 28, to, display.y - 22)
            drawLine(to + 5, display.y - 28, to, display.y - 22)
        }

        // The displays, each carrying its own third at full strength.
        for (part, display) in displays.enumerated() {
            withClip(display) {
                piece(in: display, from: Double(part) / 3, to: Double(part + 1) / 3)
            }
            noFill()
            stroke(ink)
            strokeWeight(2)
            drawRect(corner: Vector2(display.x, display.y),
                     width: display.width, height: display.height)
            noStroke()
            fill(soft)
            textSize(13)
            textAlign(.center, .top)
            drawText("display \(part + 1)", display.center.x, display.y + display.height + 10)
        }

        fill(soft)
        textSize(14)
        textAlign(.left, .top)
        drawText("Each display carries the part of the canvas its own place on the desk covers.",
                 56, 588)
    }

    /// The piece itself, drawn into `frame` from `from` to `to` of the canvas.
    /// The same function draws the whole thing and any part of it, which is what
    /// the wall does with the real one.
    private func piece(in frame: Rectangle, from: Double, to: Double) {
        let span = max(to - from, 0.0001)
        func x(_ u: Double) -> Double { frame.x + (u - from) / span * frame.width }

        // A sky in bands, so a part still shows the same sky as its neighbour.
        noStroke()
        let bands = 26
        let sky = Ramp([Color(hex: 0x0B0E1A), Color(hex: 0x1B2340), Color(hex: 0x59394A)])
        for band in 0..<bands {
            let step = frame.height * 0.62 / Double(bands)
            fill(sky.color(at: Double(band) / Double(bands)))
            drawRect(frame.x, frame.y + Double(band) * step, frame.width, step + 1)
        }
        fill(Color(hex: 0x0A0A0C))
        drawRect(frame.x, frame.y + frame.height * 0.62,
                 frame.width, frame.height * 0.38 + 1)

        // The sun, which sits in the first third and so lands on display 1.
        let sunU = 0.17
        if sunU >= from - 0.08, sunU <= to + 0.08 {
            for ring in stride(from: 4, through: 1, by: -1) {
                fill(Color(hex: 0xFAD99E, alpha: 0.07))
                drawCircle(x(sunU), frame.y + frame.height * 0.34,
                           frame.height * 0.055 * Double(ring))
            }
            fill(Color(hex: 0xFFEDC6))
            drawCircle(x(sunU), frame.y + frame.height * 0.34, frame.height * 0.05)
        }

        // One tide the length of the canvas, so a wave leaving one display
        // arrives on the next at the same height.
        var wave: [Vector2] = []
        for step in 0...160 {
            let u = from + span * Double(step) / 160
            let swell = sin(u * .tau * 3) * 0.5 + sin(u * .tau * 7 + 1.2) * 0.26
            wave.append(Vector2(x(u), frame.y + frame.height * (0.62 + swell * 0.14)))
        }
        noFill()
        stroke(Color(hex: 0xDCE8F2))
        strokeWeight(2)
        drawPolyline(wave)

        // The rule along the top, the thing you line a wall up against.
        stroke(Color(white: 1, alpha: 0.45))
        strokeWeight(1)
        var tick = (from * 50).rounded(.up) / 50
        while tick <= to {
            let long = (tick * 10).rounded() == tick * 10
            drawLine(x(tick), frame.y, x(tick), frame.y + (long ? 12 : 6))
            tick += 0.02
        }
    }
}
