// figure: frame=0 themed
//
// Guide diagram: smoothstep read as a window cutter rather than as an easing
// curve. A signal runs across the top with the two edges laid over it; the
// middle row is what smoothstep makes of it, flat at 0 below the low edge and
// swelling to 1 at the crest; the bottom row is that value spent as light, so
// the same number reads as the spotlight the chapter's payoff runs on.
import Ollin
import OllinDiagram

final class WindowCutter: Sketch {
    override var canvasSize: CanvasSize { .size(880, 600) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.26) }
    var accent: Color { theme.accent }

    /// The call the prose reads out, drawn rather than described.
    let low = 0.3
    let high = 1.0

    let left = 92.0
    let right = 788.0
    let laps = 2.0

    /// The signal: two laps of a plain wave, running -1 to 1.
    func wave(_ u: Double) -> Double { sin(u * .tau * laps - .pi / 2) }

    /// What the window makes of it.
    func lit(_ u: Double) -> Double { smoothstep(low, high, wave(u)) }

    func x(_ u: Double) -> Double { left + u * (right - left) }

    override func draw() {
        background(paper)
        textSize(20)

        signalRow(top: 72, height: 170)
        outputRow(top: 322, height: 118)
        spotlightRow(y: 528)
    }

    // MARK: the signal, with the window laid over it

    func signalRow(top: Double, height: Double) {
        let middle = top + height / 2
        // The wave runs -1 to 1 across the row, with a little headroom so its
        // trough does not sit on the edge.
        func y(_ value: Double) -> Double { middle - value * (height / 2 - 8) }

        // The window: everything above the low edge is inside it.
        noStroke()
        fill(theme.accent(0.12))
        drawRect(left, y(high), right - left, y(low) - y(high))

        // The wave, drawn faint outside the window and solid inside it, so the
        // crests the window keeps are the part you look at.
        var u = 0.0
        var below: [Vector2] = []
        var inside: [Vector2] = []
        noFill()
        strokeWeight(3.5)
        while u <= 1.0001 {
            let p = Vector2(x(u), y(wave(u)))
            if wave(u) >= low {
                inside.append(p)
                if below.count > 1 { stroke(theme.ink(0.45)); drawPolyline(below) }
                below = [p]
            } else {
                below.append(p)
                if inside.count > 1 { stroke(accent); drawPolyline(inside) }
                inside = [p]
            }
            u += 0.0015
        }
        if below.count > 1 { stroke(theme.ink(0.45)); drawPolyline(below) }
        if inside.count > 1 { stroke(accent); drawPolyline(inside) }

        // The two edges, dashed across the row and labeled at the left.
        edge(at: y(low), label: "0.3")
        edge(at: y(high), label: "1.0")

        // The band names itself, in the lap where the wave is nowhere near it.
        noStroke()
        fill(theme.ink(0.55))
        textAlign(.center, .middle)
        drawText("the window", (left + right) / 2, (y(high) + y(low)) / 2)

        noStroke()
        fill(ink)
        textAlign(.left, .bottom)
        drawText("the signal", left, top - 16)
        fill(theme.ink(0.6))
        textAlign(.right, .bottom)
        drawText("a plain wave, running -1 to 1", right, top - 16)
    }

    func edge(at y: Double, label: String) {
        stroke(theme.ink(0.55))
        strokeWeight(2)
        var x = left
        while x < right {
            drawLine(x, y, min(x + 11, right), y)
            x += 22
        }
        noStroke()
        fill(ink)
        textAlign(.right, .middle)
        drawText(label, left - 14, y)
    }

    // MARK: what smoothstep makes of it

    func outputRow(top: Double, height: Double) {
        let bottom = top + height

        stroke(faint)
        strokeWeight(1.5)
        drawLine(left, bottom, right, bottom)
        drawLine(left, top, right, top)

        var points: [Vector2] = []
        var u = 0.0
        while u <= 1.0001 {
            points.append(Vector2(x(u), bottom - lit(u) * height))
            u += 0.0015
        }
        noFill()
        stroke(accent)
        strokeWeight(3.5)
        drawPolyline(points)

        noStroke()
        fill(ink)
        textAlign(.right, .middle)
        drawText("1", left - 14, top)
        drawText("0", left - 14, bottom)
        textAlign(.left, .bottom)
        drawText("smoothstep(0.3, 1, wave)", left, top - 16)
        fill(theme.ink(0.6))
        textAlign(.right, .bottom)
        drawText("flat, then a soft shoulder, then the crest", right, top - 16)
    }

    // MARK: the same value, spent as light

    func spotlightRow(y: Double) {
        let count = 40
        for i in 0 ..< count {
            let u = (Double(i) + 0.5) / Double(count)
            let value = lit(u)
            noStroke()
            fill(Color.mix(theme.ink(0.18), accent, value))
            drawCircle(x(u), y, 4 + value * 11)
        }
        noStroke()
        fill(theme.ink(0.6))
        textAlign(.center, .top)
        drawText("the same value, spent as light: a soft spotlight rather than a switch",
                 (left + right) / 2, y + 30)
    }
}
