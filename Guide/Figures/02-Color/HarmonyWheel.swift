// figure: frame=0 themed
//
// Guide diagram: the hue wheel, and the four harmonies drawn on it. One ring
// of hues at a single OKHSL lightness, then four small wheels that mark the
// hues each harmony builder returns for the same base color, joined so the
// angle between them reads as the relation. The base wears a ring so it can
// be told from its companions in every wheel.
import Ollin
import OllinDiagram

final class HarmonyWheel: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    /// One base color, the same in every wheel.
    let base = Color(OKHSL(h: 0.05, s: 0.85, l: 0.65))

    /// Twelve hues at the base's weight, the last repeating the first so the
    /// conic sweep has no seam.
    var wheel: Ramp {
        Ramp((0...12).map { Color(OKHSL(h: Double($0) / 12, s: 0.85, l: 0.65)) }, in: .oklch)
    }

    override func draw() {
        background(theme.paper)
        noStroke()
        textSize(20)

        // The wheel itself, with the four quarter turns named.
        let center = Vector2(232, 262)
        ring(at: center, radius: 178, width: 62)
        fill(theme.ink)
        textAlign(.center, .middle)
        for (turn, name) in [(0.0, "0"), (0.25, "¼ turn"), (0.5, "½ turn"), (0.75, "¾ turn")] {
            let angle = turn * .tau
            let x = center.x + cos(angle) * 218
            let y = center.y + sin(angle) * 218
            drawText(name, x, y)
        }
        drawText("hue, as a turn of the wheel", center.x, center.y + 254)

        // The four harmonies, each on a small wheel of the same hues.
        harmony(Palette.complementary(of: base), at: Vector2(560, 138), label: "complementary")
        harmony(Palette.splitComplementary(of: base), at: Vector2(750, 138), label: "split complementary")
        harmony(Palette.triadic(of: base), at: Vector2(560, 372), label: "triadic")
        harmony(Palette.analogous(of: base, count: 5), at: Vector2(750, 372), label: "analogous")
    }

    /// A ring of the wheel's hues: a conic disk with the paper drawn back
    /// over its middle.
    func ring(at center: Vector2, radius: Double, width: Double) {
        fill(.conic(center: center, startAngle: 0, wheel))
        drawCircle(center: center, radius: radius)
        fill(theme.paper)
        drawCircle(center: center, radius: radius - width)
    }

    /// One harmony on its own wheel: a dot per color where its hue sits on
    /// the ring, chords from the base to each companion, and a label.
    func harmony(_ palette: Palette, at center: Vector2, label: String) {
        let radius = 74.0
        ring(at: center, radius: radius, width: 26)
        let points = palette.map { color -> Vector2 in
            let angle = OKHSL(color).h * .tau
            return Vector2(center.x + cos(angle) * (radius - 13),
                           center.y + sin(angle) * (radius - 13))
        }
        stroke(theme.ink)
        strokeWeight(2)
        for point in points.dropFirst() {
            drawLine(points[0], point)
        }
        noStroke()
        for (i, point) in points.enumerated() {
            fill(theme.paper)
            drawCircle(center: point, radius: 12)
            fill(palette[i])
            drawCircle(center: point, radius: 9)
        }
        noFill()
        stroke(theme.ink)
        strokeWeight(2.5)
        drawCircle(center: points[0], radius: 15)
        noStroke()
        fill(theme.ink)
        textAlign(.center, .top)
        drawText(label, center.x, center.y + radius + 16)
    }
}
