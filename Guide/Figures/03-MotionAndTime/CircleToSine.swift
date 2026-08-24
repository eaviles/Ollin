// figure: frame=0 themed
//
// Guide diagram: where the sine wave comes from. A point walks a circle; its
// height, traced over time, is the wave. One full turn of the circle is one
// full cycle of the wave (the period), and the circle's radius is the swing.
import Ollin

final class CircleToSine: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var faint: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.28) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }

    override func draw() {
        background(paper)

        let center = Vector2(190, 250)
        let radius = 120.0
        let angle = Double.tau / 12          // 30 degrees: mid-swing, easy to read
        let waveLeft = 400.0, waveRight = 850.0
        let turns = 2.0

        func waveX(_ a: Double) -> Double {
            waveLeft + a / (.tau * turns) * (waveRight - waveLeft)
        }
        func waveY(_ a: Double) -> Double {
            center.y - sin(a) * radius
        }

        // The shared zero line, from the circle's center through the wave.
        stroke(faint)
        strokeWeight(2)
        drawLine(center.x - radius - 30, center.y, waveRight, center.y)

        // The circle and the point on its rim.
        noFill()
        stroke(faint)
        drawCircle(center: center, radius: radius)
        let point = Vector2(center.x + cos(angle) * radius,
                            center.y - sin(angle) * radius)
        stroke(ink)
        strokeWeight(3)
        drawLine(center.x, center.y, point.x, point.y)
        stroke(ink)
        strokeWeight(2.5)
        drawArc(center.x, center.y, 44, 44, start: -angle, stop: 0)
        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.left, .middle)
        drawText("angle", center.x + 54, center.y - 22)
        fill(ink)
        drawCircle(center: center, radius: 5)

        // The wave: the point's height at every angle so far.
        var points: [Vector2] = []
        var a = 0.0
        while a <= .tau * turns {
            points.append(Vector2(waveX(a), waveY(a)))
            a += 0.02
        }
        noFill()
        stroke(ink)
        strokeWeight(3)
        drawPolyline(points)

        // The dashed height link: same height on the circle and on the wave.
        stroke(accent)
        strokeWeight(2)
        var x = point.x + 14
        while x < waveX(angle) - 10 {
            drawLine(x, point.y, min(x + 12, waveX(angle) - 10), point.y)
            x += 24
        }
        noStroke()
        fill(ink)
        textAlign(.center, .bottom)
        drawText("the same height", (point.x + waveX(angle)) / 2, point.y - 12)

        // The two dots: on the rim, and on the wave.
        fill(accent)
        drawCircle(center: point, radius: 9)
        drawCircle(waveX(angle), waveY(angle), 9)

        // Period bracket: one full turn along the zero line.
        let x0 = waveX(0), x1 = waveX(.tau)
        stroke(ink)
        strokeWeight(2)
        drawLine(x0, 470, x1, 470)
        drawLine(x0, 462, x0, 478)
        drawLine(x1, 462, x1, 478)
        noStroke()
        fill(ink)
        textAlign(.center, .top)
        drawText("one full turn = one cycle (the period)", (x0 + x1) / 2, 484)

        // Swing marker: zero line up to a crest equals the radius.
        let crestX = waveX(.tau * 1.25)
        stroke(faint)
        strokeWeight(2)
        drawLine(crestX, center.y, crestX, center.y - radius)
        noStroke()
        fill(ink)
        textAlign(.left, .middle)
        drawText("swing = radius", crestX + 12, center.y - radius / 2)

        // Caption for the circle half.
        textAlign(.center, .top)
        drawText("a point walks the circle", center.x, center.y + radius + 36)
        drawText("its height, traced over time", (waveLeft + waveRight) / 2, center.y + radius + 36)
    }
}
