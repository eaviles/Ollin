// figure: frame=0 probe themed
//
// Guide diagram: a Timeline's value over its whole run, sampled by advancing
// a fresh timeline in small steps. Keyframes are dots; each segment carries
// its own easing, and the hold sits flat between them.
import Ollin

final class TimelineCurve: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var faint: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.28) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }

    override func draw() {
        background(paper)
        textSize(20)

        let left = 90.0, right = 800.0
        let baseY = 400.0, topY = 140.0
        let total = 2.8

        func plotX(_ seconds: Double) -> Double { left + seconds / total * (right - left) }
        func plotY(_ value: Double) -> Double { baseY - value * (baseY - topY) }

        // Axes: seconds along the bottom, the value rising on the left.
        stroke(faint)
        strokeWeight(2)
        drawLine(left, baseY, right, baseY)
        for s in 0...2 {
            let x = plotX(Double(s))
            drawLine(x, baseY - 6, x, baseY + 6)
        }
        noStroke()
        fill(ink)
        textAlign(.center, .top)
        for s in 0...2 {
            drawText("\(s)s", plotX(Double(s)), baseY + 14)
        }

        // Sample the timeline by advancing it in small steps.
        let move = Timeline(0.0)
            .to(1.0, in: 1.2, ease: .easeInOut)
            .hold(for: 0.6)
            .to(0.25, in: 1.0, ease: .easeOutBounce)

        var points: [Vector2] = []
        var clock = 0.0
        while clock <= total + 0.0001 {
            points.append(Vector2(plotX(clock), plotY(move.value)))
            move.advance(by: 0.004)
            clock += 0.004
        }
        noFill()
        stroke(ink)
        strokeWeight(3.5)
        drawPolyline(points)

        // Keyframes: where each segment hands off to the next.
        noStroke()
        fill(accent)
        drawCircle(plotX(0), plotY(0), 8)
        drawCircle(plotX(1.2), plotY(1), 8)
        drawCircle(plotX(1.8), plotY(1), 8)
        drawCircle(plotX(2.8), plotY(0.25), 8)

        // Segment labels.
        textSize(18)
        fill(ink)
        textAlign(.center, .bottom)
        drawText(".to(1, in: 1.2, ease: .easeInOut)", plotX(0.55), plotY(1.0) - 44)
        textAlign(.center, .top)
        drawText(".hold(for: 0.6)", plotX(1.5), plotY(1.0) + 18)
        textAlign(.center, .bottom)
        drawText(".to(0.25, in: 1, ease: .easeOutBounce)", plotX(2.22), plotY(1.0) - 44)
    }
}
