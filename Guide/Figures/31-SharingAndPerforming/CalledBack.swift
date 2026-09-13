// figure: frame=0 themed
//
// Guide diagram (Chapter 31): a cue called back over a fade. Three looks of
// one small piece, the same ring of dots: the night look, the piece one second
// into cue("dawn", over: 2), and dawn. Under them, what each parameter did
// across the two seconds: the size and the hue ease, slow at both ends; the
// ground color blends, drawn as the band the timeline draws; the switch has
// nothing between its two values, so it took the cue's value on the first
// frame, which is why the halfway look is already lit. At the left, the sheet
// the looks were saved to.
import Ollin
import OllinDiagram

final class CalledBack: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    /// A look: every parameter at once.
    struct Look {
        var size: Double
        var hue: Double
        var ground: Color
        var lit: Bool
    }

    let night = Look(size: 12, hue: 0.62, ground: Color(hex: 0x14162B), lit: false)
    let dawn = Look(size: 24, hue: 0.08, ground: Color(hex: 0xF3E7D3), lit: true)

    private func ease(_ u: Double) -> Double { u * u * (3 - 2 * u) }
    private func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    /// The look at `t` seconds into a two-second fade: the numbers and the
    /// color ease, and the switch is the cue's from the first frame on.
    func look(at t: Double) -> Look {
        let e = ease(t / 2)
        return Look(size: mix(night.size, dawn.size, e),
                    hue: mix(night.hue, dawn.hue, e),
                    ground: night.ground.mixed(with: dawn.ground, e),
                    lit: t > 0 ? dawn.lit : night.lit)
    }

    override func draw() {
        background(theme.paper)
        textFont(.system)

        let laneLeft = 240.0, laneRight = 680.0
        func tx(_ t: Double) -> Double { laneLeft + t / 2 * (laneRight - laneLeft) }

        // The three looks, each over its moment on the lanes below.
        let side = 150.0, top = 52.0
        let moments: [(Double, String)] = [(0, "night"), (1, "one second in"), (2, "dawn")]
        for (t, name) in moments {
            let frame = Rectangle(x: tx(t) - side / 2, y: top, width: side, height: side)
            drawLook(look(at: t), in: frame)
            noStroke()
            drawText(name, frame.center.x, top + side + 14, size: 14, color: theme.ink,
                     align: .center, .middle)
        }
        drawText("cue(\"dawn\", over: 2)", tx(1), 22, size: 15, color: theme.ink,
                 align: .center, .middle)
        stroke(theme.accent)
        strokeWeight(2)
        drawArrow(from: Vector2(tx(0) + side / 2 + 8, top + side / 2),
                  to: Vector2(tx(1) - side / 2 - 8, top + side / 2))
        drawArrow(from: Vector2(tx(1) + side / 2 + 8, top + side / 2),
                  to: Vector2(tx(2) - side / 2 - 8, top + side / 2))

        // The sheet the looks live in.
        let sheet = Rectangle(x: 28, y: 250, width: 112, height: 176)
        fill(theme.card)
        stroke(theme.border)
        strokeWeight(1.5)
        drawRect(sheet, cornerRadius: 8)
        noStroke()
        drawText("Sketch.cues.json", sheet.x + 8, sheet.y + 14, size: 10, color: theme.muted,
                 align: .left, .middle)
        for (i, name) in ["night", "dawn", "storm", "noon", "dusk"].enumerated() {
            let y = sheet.y + 40 + Double(i) * 26
            if name == "dawn" {
                fill(theme.accent)
                drawCircle(sheet.x + 16, y, 3.5)
            }
            drawText(name, sheet.x + 28, y, size: 13, color: theme.ink, align: .left, .middle)
        }

        // The lanes: what each parameter did across the two seconds.
        let lanes: [(String, Double, String)] = [
            ("size", 268, "eases, slow at both ends"),
            ("hue", 318, "eases, slow at both ends"),
            ("ground", 368, "the blend, as a band"),
            ("lit", 418, "flips on the first frame"),
        ]
        for (name, y, note) in lanes {
            noStroke()
            fill(theme.card)
            drawRect(laneLeft, y - 18, laneRight - laneLeft, 36, cornerRadius: 4)
            drawText(name, 222, y, size: 14, color: theme.ink, align: .right, .middle)
            drawText(note, laneRight + 14, y, size: 12, color: theme.muted, align: .left, .middle)
        }
        // size and hue: the eased curves. The size climbs, the hue falls.
        for (y, rising) in [(268.0, true), (318.0, false)] {
            stroke(theme.accent(0.75))
            strokeWeight(2)
            var last = Vector2(tx(0), y + (rising ? 12 : -12))
            for i in 1...120 {
                let t = Double(i) / 120 * 2
                let e = ease(t / 2)
                let p = Vector2(tx(t), y + (rising ? 12 - 24 * e : -12 + 24 * e))
                drawLine(last, p)
                last = p
            }
        }
        // ground: the blend, sampled along the lane.
        noStroke()
        var x = laneLeft
        while x < laneRight {
            let t = (x + 1.5 - laneLeft) / (laneRight - laneLeft) * 2
            fill(look(at: t).ground)
            drawRect(x, 368 - 6, 3.5, 12)
            x += 3
        }
        // lit: the step, on the first frame of the fade.
        stroke(theme.accent(0.75))
        strokeWeight(2)
        let firstFrame = tx(1.0 / 60)
        drawLine(tx(0), 418 + 12, firstFrame, 418 + 12)
        drawLine(firstFrame, 418 + 12, firstFrame, 418 - 12)
        drawLine(firstFrame, 418 - 12, tx(2), 418 - 12)

        // The moment the middle look was taken, and the axis of seconds.
        stroke(theme.accent(0.6))
        strokeWeight(1)
        drawLine(tx(1), 244, tx(1), 442)
        stroke(theme.ink(0.5))
        drawLine(laneLeft, 452, laneRight, 452)
        for s in 0...2 {
            drawLine(tx(Double(s)), 448, tx(Double(s)), 456)
            noStroke()
            drawText("\(s) s", tx(Double(s)), 462, size: 11, color: theme.muted, align: .center, .top)
            stroke(theme.ink(0.5))
        }

        diagramCaption("every parameter at once: the numbers ease, the color blends, the switch flips",
                       at: 492, theme: theme)
        noStroke()
        drawText("the sheet lives beside the sketch as Sketch.cues.json; a key, a pad, a program change, /ollin/cue, or --cue calls one",
                 width / 2, 520, size: 13, color: theme.muted, align: .center, .top)
    }

    /// The piece at one look: a ring of twelve dots on a ground, lit dots
    /// carrying a bright core.
    private func drawLook(_ look: Look, in frame: Rectangle) {
        noStroke()
        fill(look.ground)
        drawRect(frame, cornerRadius: 10)
        let c = frame.center, ring = frame.width * 0.32
        for i in 0..<12 {
            let a = Double(i) / 12 * .tau
            let tone = (look.hue + Double(i) / 12 * 0.18).truncatingRemainder(dividingBy: 1)
            let p = c + Vector2(cos(a), sin(a)) * ring
            let r = look.size * frame.width / 150
            fill(Color(hue: tone, saturation: look.lit ? 0.9 : 0.55,
                       brightness: look.lit ? 1 : 0.72, alpha: 0.9))
            drawCircle(center: p, radius: r)
            if look.lit {
                fill(Color(white: 1, alpha: 0.9))
                drawCircle(center: p, radius: r * 0.3)
            }
        }
        noFill()
        stroke(theme.border)
        strokeWeight(1)
        drawRect(frame, cornerRadius: 10)
    }
}
