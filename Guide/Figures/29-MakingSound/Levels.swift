// figure: frame=0 themed
//
// Guide diagram (Chapter 29): the three effects that hold a level. Three
// panels: the curve a compressor puts between what comes in and what leaves,
// at three ratios and with a knee; the attack and the release as the lag
// between a level that steps up and the gain that answers it; and the gate,
// where a note decaying through the threshold is kept open by the hold before
// it closes. The curves are the ones the code is written from, which the tests
// pin the running code to.
import Ollin
import OllinDiagram

final class Levels: Sketch {
    override var canvasSize: CanvasSize { .size(880, 340) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.5) }
    var faint: Color { theme.ink(0.16) }
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        let panels = [Rectangle(x: 40, y: 44, width: 250, height: 210),
                      Rectangle(x: 315, y: 44, width: 250, height: 210),
                      Rectangle(x: 590, y: 44, width: 250, height: 210)]
        diagramFrame(panels[0], title: "the curve", theme: theme)
        drawCurve(in: panels[0])
        diagramFrame(panels[1], title: "attack and release", theme: theme)
        drawTimes(in: panels[1])
        diagramFrame(panels[2], title: "the gate, and its hold", theme: theme)
        drawGate(in: panels[2])

        diagramCaption("a level measured, and what each of the three does about it", at: 290, theme: theme)
    }

    /// The static curve, in decibels both ways over −48…0: a corner at −24
    /// with slopes 1/2 and 1/4, the limiter flat at its ceiling, and the same
    /// four-to-one curve again with a knee twelve wide bending across it.
    private func drawCurve(in panel: Rectangle) {
        let inset = inset(panel, 20, 22)
        let threshold = -24.0
        func point(_ input: Double, _ output: Double) -> Vector2 {
            Vector2(inset.x + inset.width * (input + 48) / 48,
                    inset.bottomRight.y - inset.height * (output + 48) / 48)
        }
        /// What a level leaves at, given a ratio and how wide the knee is.
        func out(_ input: Double, ratio: Double, knee: Double) -> Double {
            let over = input - threshold
            if knee > 0 && abs(2 * over) <= knee {
                return input - (1 - 1 / ratio) * (over + knee / 2) * (over + knee / 2) / (2 * knee)
            }
            return over > 0 ? threshold + over / ratio : input
        }

        noFill()
        stroke(faint)
        strokeWeight(1)
        drawLine(point(-48, -48), point(0, 0))
        drawLine(point(threshold, -48), point(threshold, 0))

        let count = 120
        func curve(ratio: Double, knee: Double, color: Color, weight: Double) {
            stroke(color)
            strokeWeight(weight)
            drawPolyline((0...count).map { step in
                let input = -48 + 48 * Double(step) / Double(count)
                return point(input, out(input, ratio: ratio, knee: knee))
            })
        }
        curve(ratio: 2, knee: 0, color: soft, weight: 1.5)
        curve(ratio: 4, knee: 12, color: soft, weight: 1.5)
        curve(ratio: 4, knee: 0, color: accent, weight: 2.5)
        stroke(soft)
        strokeWeight(1.5)
        drawLine(point(-8, -8), point(0, -8))

        label("2 to 1", at: point(-6, -15) + Vector2(0, -16), align: .right)
        label("4 to 1", at: point(-6, -19.5) + Vector2(0, 2), align: .right)
        label("a ceiling", at: point(-8, -8) + Vector2(-3, -16), align: .right)
        label("a knee, before the corner", at: point(-46, -30), align: .left)
        label("threshold", at: point(threshold, -48) + Vector2(3, -16), align: .left)
        axis(inset, left: "−48 dB in", right: "0 dB out")
    }

    /// A level that steps up and back down, and the gain reduction answering
    /// it: most of the way in one attack, most of the way back in one release.
    private func drawTimes(in panel: Rectangle) {
        let inset = inset(panel, 20, 22)
        let seconds = 0.9, attack = 0.05, release = 0.2
        let step = (start: 0.15, end: 0.5)
        func x(_ t: Double) -> Double { inset.x + inset.width * t / seconds }
        func y(_ v: Double) -> Double { inset.bottomRight.y - inset.height * v }

        // What comes in, up top: quiet, loud, quiet again.
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawPolyline([Vector2(x(0), y(0.66)), Vector2(x(step.start), y(0.66)),
                      Vector2(x(step.start), y(0.94)), Vector2(x(step.end), y(0.94)),
                      Vector2(x(step.end), y(0.66)), Vector2(x(seconds), y(0.66))])

        // The reduction under it: one pole toward the depth it wants, at
        // whichever of the two times applies.
        var reduction = 0.0
        var trace: [Vector2] = []
        let dt = seconds / 300
        for tick in 0...300 {
            let t = Double(tick) * dt
            let wanted = (t >= step.start && t < step.end) ? 0.42 : 0.0
            let time = wanted > reduction ? attack : release
            reduction += (wanted - reduction) * (1 - exp(-dt / time))
            trace.append(Vector2(x(t), y(0.06 + reduction)))
        }
        stroke(accent)
        strokeWeight(2.5)
        drawPolyline(trace)

        stroke(faint)
        strokeWeight(1)
        drawLine(x(step.start), y(0.06), x(step.start), y(0.94))
        drawLine(x(step.end), y(0.06), x(step.end), y(0.94))
        stroke(soft)
        drawLine(x(step.start), y(0.33), x(step.start + attack), y(0.33))
        drawLine(x(step.end), y(0.33), x(step.end + release), y(0.33))

        label("what came in", at: Vector2(x(0.02), y(0.66) - 16), align: .left)
        label("one attack", at: Vector2(x(step.start + attack) + 3, y(0.33) - 15), align: .left)
        label("one release", at: Vector2(x(step.end + release) + 3, y(0.33) - 15), align: .left)
        label("how much it holds down", at: Vector2(x(0.02), y(0.06) + 2), align: .left)
        axis(inset, left: "0 s", right: "0.9 s")
    }

    /// A note decaying through the threshold, and the gate under it: open
    /// while the level is over the line, held open past it, then closing.
    private func drawGate(in panel: Rectangle) {
        let inset = inset(panel, 20, 22)
        let seconds = 1.2, threshold = 0.22, hold = 0.28, release = 0.12
        func x(_ t: Double) -> Double { inset.x + inset.width * t / seconds }
        func y(_ v: Double) -> Double { inset.bottomRight.y - inset.height * v * 0.9 }
        func level(_ t: Double) -> Double { 0.9 * exp(-t * 2.4) }

        noFill()
        stroke(faint)
        strokeWeight(1)
        drawLine(x(0), y(threshold), x(seconds), y(threshold))

        stroke(soft)
        strokeWeight(2)
        drawPolyline((0...200).map { step in
            let t = seconds * Double(step) / 200
            return Vector2(x(t), y(level(t)))
        })

        // The gate: open until the level has been under the line for a hold,
        // then closing over the release. Drawn twice, with the hold and
        // without, since the difference between them is the point.
        let crossing = -log(threshold / 0.9) / 2.4
        func gated(_ hold: Double) -> [Vector2] {
            (0...200).map { step in
                let t = seconds * Double(step) / 200
                let shut = t - (crossing + hold)
                let gain = shut <= 0 ? 1 : max(0, 1 - shut / release)
                return Vector2(x(t), y(level(t) * gain))
            }
        }
        stroke(theme.accent(0.45))
        strokeWeight(1.5)
        drawPolyline(gated(0))
        stroke(accent)
        strokeWeight(2.5)
        drawPolyline(gated(hold))

        stroke(faint)
        strokeWeight(1)
        drawLine(x(crossing), y(threshold), x(crossing), y(0))
        drawLine(x(crossing + hold), y(threshold), x(crossing + hold), y(0))

        label("threshold", at: Vector2(x(seconds) - 4, y(threshold) - 16), align: .right)
        label("hold", at: Vector2(x(crossing + hold / 2), y(threshold) + 3), align: .center)
        label("the note", at: Vector2(x(0.06), y(0.62)), align: .left)
        label("no hold", at: Vector2(x(crossing + release) - 3, y(0.03)), align: .right)
        axis(inset, left: "0 s", right: "1.2 s")
    }

    private func inset(_ r: Rectangle, _ dx: Double, _ dy: Double) -> Rectangle {
        Rectangle(x: r.x + dx, y: r.y + dy, width: r.width - 2 * dx, height: r.height - 2 * dy)
    }

    private func label(_ text: String, at point: Vector2, align: HorizontalTextAlign) {
        noStroke()
        fill(soft)
        textSize(11)
        textAlign(align, .top)
        drawText(text, at: point)
    }

    private func axis(_ inset: Rectangle, left: String, right: String) {
        noStroke()
        fill(soft)
        textSize(11)
        textAlign(.left, .bottom)
        drawText(left, inset.x, inset.bottomRight.y + 18)
        textAlign(.right, .bottom)
        drawText(right, inset.topRight.x, inset.bottomRight.y + 18)
    }
}
