// figure: frame=0 themed
//
// Guide diagram: the four gradient geometries. A ramp laid along a line,
// out from a center, once around a center, and along a stroked path.
import Ollin
import OllinDiagram

final class GradientPaint: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var label: Color { theme.ink(0.72) }

    override func draw() {
        background(paper)
        noStroke()
        textSize(16)
        textAlign(.center, .top)

        let dusk = Ramp([
            Color(hex: 0x14213D), Color(hex: 0x5E60CE),
            Color(hex: 0xE56B6F), Color(hex: 0xFFB703),
        ])

        // Linear: start point to end point.
        fill(.linear(from: Vector2(40, 100), to: Vector2(40, 400), dusk))
        drawRect(40, 100, 180, 300)
        caption(".linear(from:to:)", 130)

        // Radial: center out to a radius, fading to clear.
        let glow = Ramp(stops: [(0, Color(hex: 0xE4572E)),
                                (0.4, Color(hex: 0xE4572E)),
                                (1, Color(hex: 0xE4572E, alpha: 0))])
        fill(.radial(center: Vector2(340, 250), radius: 108, glow))
        drawCircle(340, 250, 108)
        caption(".radial(center:radius:)", 340)

        // Conic: once around a center, from twelve o'clock; the ramp's last
        // color repeats its first, so the seam does not show.
        let wheel = Ramp((0...10).map { Color(hue: Double($0) / 10, saturation: 0.8, brightness: 0.95) })
        fill(.conic(center: Vector2(550, 250), startAngle: -.pi / 2, wheel))
        drawCircle(550, 250, 96)
        caption(".conic(center:startAngle:)", 550)

        // Along the path: the ramp runs along the stroke itself.
        noFill()
        stroke(.alongPath(wheel))
        strokeWeight(22)
        drawCircle(760, 250, 84)
        noStroke()
        caption(".alongPath(...)", 760)
    }

    func caption(_ text: String, _ x: Double) {
        fill(label)
        drawText(text, x, 452)
    }
}
