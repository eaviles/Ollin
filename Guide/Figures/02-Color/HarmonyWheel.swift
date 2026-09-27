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

        // The wheel itself, with the four quarter turns named beside it. Each
        // label is aligned away from the ring, so the one on the left ends
        // short of the canvas edge instead of straddling it.
        let center = Vector2(250, 258)
        let radius = 160.0
        ring(at: center, radius: radius, width: 56)
        fill(theme.ink)
        let gap = radius + 14
        textAlign(.left, .middle)
        drawText("0", center.x + gap, center.y)
        textAlign(.center, .top)
        drawText("¼ turn", center.x, center.y + gap)
        textAlign(.right, .middle)
        drawText("½ turn", center.x - gap, center.y)
        textAlign(.center, .bottom)
        drawText("¾ turn", center.x, center.y - gap)
        textAlign(.center, .middle)
        drawText("hue, as a turn of the wheel", center.x, center.y + 242)

        // The four harmonies, each on a small wheel of the same hues, spaced
        // so the two longest captions keep clear of each other.
        harmony(Palette.complementary(of: base), at: Vector2(548, 138), label: "complementary")
        harmony(Palette.splitComplementary(of: base), at: Vector2(762, 138), label: "split complementary")
        harmony(Palette.triadic(of: base), at: Vector2(548, 372), label: "triadic")
        harmony(Palette.analogous(of: base, count: 5), at: Vector2(762, 372), label: "analogous")
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
    /// the ring, chords from the base to each companion, and a label. The
    /// base is found by value, since the analogous builder centers it in its
    /// list rather than putting it first.
    func harmony(_ palette: Palette, at center: Vector2, label: String) {
        let radius = 74.0
        ring(at: center, radius: radius, width: 26)
        let colors = Array(palette)
        let baseIndex = colors.firstIndex(of: base) ?? 0
        let points = colors.map { color -> Vector2 in
            let angle = OKHSL(color).h * .tau
            return Vector2(center.x + cos(angle) * (radius - 13),
                           center.y + sin(angle) * (radius - 13))
        }
        stroke(theme.ink)
        strokeWeight(2)
        for (i, point) in points.enumerated() where i != baseIndex {
            drawLine(points[baseIndex], point)
        }
        noStroke()
        for (i, point) in points.enumerated() {
            fill(theme.paper)
            drawCircle(center: point, radius: 12)
            fill(colors[i])
            drawCircle(center: point, radius: 9)
        }
        noFill()
        stroke(theme.ink)
        strokeWeight(2.5)
        drawCircle(center: points[baseIndex], radius: 15)
        noStroke()
        fill(theme.ink)
        textAlign(.center, .top)
        drawText(label, center.x, center.y + radius + 16)
    }
}
