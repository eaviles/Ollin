// figure: frame=0 themed
//
// Guide diagram (Appendix B): barycentric coordinates. Left, a triangle with
// corners a, b, and c and one point inside it, made of 0.5 of a, 0.3 of b,
// and 0.2 of c. Lines from the point to the corners cut the triangle into
// three smaller ones, and each weight is the share of the area opposite its
// corner. Right, the same triangle filled with dots, each colored by mixing
// the three corner colors in its own weights, in linear light as Ollin mixes.
// The corner colors depict content, so they stay put in the dark render.
import Ollin
import OllinDiagram

final class Barycentric: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    let weights = (a: 0.5, b: 0.3, c: 0.2)
    let colorA = Color(hex: 0xE4572E)
    let colorB = Color(hex: 0x2E86AB)
    let colorC = Color(hex: 0xF2C14E)

    func corners(offsetBy dx: Double) -> (a: Vector2, b: Vector2, c: Vector2) {
        (Vector2(70 + dx, 400), Vector2(370 + dx, 400), Vector2(200 + dx, 110))
    }

    override func draw() {
        background(theme.paper)
        weightsPanel()
        blendPanel()
        diagramCaption("three weights that add to 1 name any point in a triangle", at: 488, theme: theme)
    }

    func weightsPanel() {
        let t = corners(offsetBy: 0)
        let p = t.a * weights.a + t.b * weights.b + t.c * weights.c

        noStroke()
        fill(theme.ink(0.06))
        drawPolygon([p, t.b, t.c])
        fill(theme.ink(0.12))
        drawPolygon([p, t.c, t.a])
        fill(theme.ink(0.18))
        drawPolygon([p, t.a, t.b])

        stroke(theme.ink(0.45))
        strokeWeight(1.5)
        for corner in [t.a, t.b, t.c] {
            drawLine(p, corner)
        }
        stroke(theme.ink)
        strokeWeight(2.5)
        drawPolyline([t.a, t.b, t.c], closed: true)

        noStroke()
        fill(theme.accent)
        drawCircle(center: p, radius: 7)

        textSize(17)
        fill(theme.ink)
        label("a", at: t.a + Vector2(-16, 14))
        label("b", at: t.b + Vector2(16, 14))
        label("c", at: t.c + Vector2(0, -18))

        // Each weight sits in the small triangle opposite its corner. The one
        // opposite b is narrow, so its label sits low, where it is widest.
        textSize(15)
        fill(theme.ink)
        label("\(weights.a) of a", at: (p + t.b + t.c) / 3)
        label("\(weights.b) of b", at: (p + t.c + t.a) / 3 + Vector2(-6, 36))
        label("\(weights.c) of c", at: (p + t.a + t.b) / 3)
    }

    func blendPanel() {
        let t = corners(offsetBy: 420)
        let steps = 42

        noStroke()
        for i in 0...steps {
            for j in 0...(steps - i) {
                let wa = Double(i) / Double(steps)
                let wb = Double(j) / Double(steps)
                let wc = 1 - wa - wb
                let spot = t.a * wa + t.b * wb + t.c * wc
                // The weights mix light, not the stored numbers.
                fill(Color(linear: colorA.linearRGB * wa + colorB.linearRGB * wb
                                   + colorC.linearRGB * wc))
                drawCircle(center: spot, radius: 3.4)
            }
        }

        textSize(17)
        fill(theme.ink)
        label("a", at: t.a + Vector2(-16, 14))
        label("b", at: t.b + Vector2(16, 14))
        label("c", at: t.c + Vector2(0, -18))
        textSize(15)
        fill(theme.muted)
        label("each dot mixes the corners' colors in its own weights",
              at: Vector2((t.a.x + t.b.x) / 2, t.a.y + 44))
    }

    func label(_ text: String, at p: Vector2) {
        textAlign(.center, .middle)
        drawText(text, at: p)
    }
}
