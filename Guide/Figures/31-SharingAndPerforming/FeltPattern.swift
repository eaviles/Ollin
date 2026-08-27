// figure: frame=0 themed
//
// Guide diagram (Chapter 31): what a trackpad makes of a felt pattern. The
// same phrase twice: on the left as it was written, a tap and a rising hum and
// a last tap, with height standing for strength; on the right the knocks a
// trackpad is actually asked for, measured from the plan rather than drawn by
// hand, so the fade reads as a thinning run rather than a lower one.
import Ollin
import OllinDiagram
import OllinHaptics

final class FeltPattern: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    /// One tap, a hum that fades in and out under it, and a tap to close.
    private var phrase: HapticPattern {
        HapticPattern.tap(intensity: 0.9, sharpness: 0.9)
            .over(.hum(1.05, intensity: 0.7, sharpness: 0.2, fadeIn: 0.85, fadeOut: 0.2)
                .delayed(by: 0.15))
            .over(.tap(intensity: 0.7, sharpness: 0.5).delayed(by: 1.3))
    }

    override func draw() {
        background(theme.paper)
        let span = 1.45
        let left = Rectangle(x: 55, y: 60, width: 330, height: 300)
        let right = Rectangle(x: 495, y: 60, width: 330, height: 300)

        drawAsWritten(phrase, in: left, span: span)
        drawAsFelt(TrackpadPlan.knocks(for: phrase), in: right, span: span)
        diagramCaption("the same phrase, and the knocks a trackpad turns it into",
                       at: 412, theme: theme)
    }

    /// The pattern as the sketch says it: height is strength, and a hum is a
    /// solid band whose top follows its fades.
    private func drawAsWritten(_ pattern: HapticPattern, in panel: Rectangle, span: Double) {
        diagramFrame(panel, title: "as written", theme: theme)
        let base = panel.y + panel.height - 46
        let tall = panel.height - 90
        baseline(panel, at: base)

        for event in pattern.events where event.kind == .hum {
            var steps: [Vector2] = []
            var offset = 0.0
            while offset <= event.duration {
                let level = event.strength(at: offset)
                steps.append(Vector2(x(event.time + offset, panel, span), base - tall * level))
                offset += 0.01
            }
            withState {
                noStroke()
                fill(theme.accent(0.34))
                drawPolygon([Vector2(steps.first!.x, base)] + steps + [Vector2(steps.last!.x, base)])
            }
        }

        for event in pattern.events where event.kind == .tap {
            withState {
                stroke(theme.ink)
                strokeWeight(3)
                let at = x(event.time, panel, span)
                drawLine(at, base, at, base - tall * event.intensity)
                noStroke()
                fill(theme.ink)
                drawCircle(at, base - tall * event.intensity, 5)
            }
        }

        drawText("strength", panel.x + 14, panel.y + 26,
                 size: 15, color: theme.muted, align: .left, .middle)
    }

    /// The plan: every knock the same height, because the hardware has one
    /// strength. What carries the fade is how close together they stand.
    private func drawAsFelt(_ knocks: [TrackpadKnock], in panel: Rectangle, span: Double) {
        diagramFrame(panel, title: "as a trackpad feels it", theme: theme)
        let base = panel.y + panel.height - 46
        baseline(panel, at: base)

        for knock in knocks {
            let tall = switch knock.feel {
            case .soft: 34.0
            case .level: 52.0
            case .crisp: 74.0
            }
            withState {
                stroke(knock.feel == .crisp ? theme.ink : theme.accent(0.85))
                strokeWeight(3)
                let at = x(knock.time, panel, span)
                drawLine(at, base, at, base - tall)
            }
        }

        drawText("\(knocks.count) knocks, one strength", panel.x + 14, panel.y + 26,
                 size: 15, color: theme.muted, align: .left, .middle)
    }

    private func baseline(_ panel: Rectangle, at y: Double) {
        withState {
            stroke(theme.border)
            strokeWeight(2)
            drawLine(panel.x + 14, y, panel.x + panel.width - 14, y)
        }
        drawText("time", panel.x + panel.width - 14, y + 22,
                 size: 15, color: theme.muted, align: .right, .middle)
    }

    private func x(_ time: Double, _ panel: Rectangle, _ span: Double) -> Double {
        panel.x + 24 + (panel.width - 48) * (time / span)
    }
}
