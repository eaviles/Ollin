// figure: frame=0 themed
//
// Guide diagram: the three gradient geometries. A ramp laid along a line,
// out from a center, and around a stroked path.
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
        textSize(20)
        textAlign(.center, .top)

        let dusk = Ramp([
            Color(hex: 0x14213D), Color(hex: 0x5E60CE),
            Color(hex: 0xE56B6F), Color(hex: 0xFFB703),
        ])

        // Linear: start point to end point.
        fill(.linear(from: Vector2(60, 100), to: Vector2(60, 400), dusk))
        drawRect(60, 100, 240, 300)
        caption(".linear(from:to:)", 180)

        // Radial: center out to a radius, fading to clear.
        let glow = Ramp(stops: [(0, Color(hex: 0xE4572E)),
                                (0.4, Color(hex: 0xE4572E)),
                                (1, Color(hex: 0xE4572E, alpha: 0))])
        fill(.radial(center: Vector2(440, 250), radius: 145, glow))
        drawCircle(440, 250, 145)
        caption(".radial(center:radius:)", 440)

        // Along the path: the ramp sweeps around the stroke.
        let wheel = Ramp((0...10).map { Color(hue: Double($0) / 10, saturation: 0.8, brightness: 0.95) })
        noFill()
        stroke(.alongPath(wheel))
        strokeWeight(26)
        drawCircle(700, 250, 118)
        noStroke()
        caption(".alongPath(...)", 700)
    }

    func caption(_ text: String, _ x: Double) {
        fill(label)
        drawText(text, x, 452)
    }
}
