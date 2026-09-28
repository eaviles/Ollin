// figure: frame=0 themed
//
// Guide diagram (Appendix B): linear light against the numbers a picture
// stores. Left, the sRGB encoding curve: light across, the stored number up,
// with half the light marked (stored as about 0.74) and a stored 0.5 marked
// (about a fifth of the light). Right, two strips of nine swatches: equal
// steps of the stored number, and equal steps of light, which crowd toward
// white. The swatches depict content, so they stay put in the dark render.
import Ollin
import OllinDiagram

final class LinearLight: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    /// Light (0...1) to the number an sRGB picture stores for it.
    func encoded(_ light: Double) -> Double {
        light <= 0.0031308 ? 12.92 * light : 1.055 * pow(light, 1 / 2.4) - 0.055
    }

    override func draw() {
        background(theme.paper)
        curvePanel(Rectangle(x: 70, y: 80, width: 320, height: 320))
        stripsPanel(Rectangle(x: 470, y: 80, width: 360, height: 320))
        diagramCaption("the stored number is not the amount of light", at: 488, theme: theme)
    }

    func curvePanel(_ r: Rectangle) {
        func point(_ light: Double, _ stored: Double) -> Vector2 {
            Vector2(r.x + light * r.width, r.y + r.height - stored * r.height)
        }

        diagramFrame(r, title: "light in, stored number out", theme: theme)

        // The straight line a stored number would follow if it were light.
        stroke(theme.ink(0.25))
        strokeWeight(1.5)
        drawLine(point(0, 0), point(1, 1))

        stroke(theme.ink)
        strokeWeight(3)
        drawPolyline((0...100).map { i in
            let light = Double(i) / 100
            return point(light, encoded(light))
        })

        // Half the light, and half the stored number.
        let half = encoded(0.5)
        let fifth = 0.214
        strokeDash([6, 5])
        stroke(theme.accent)
        strokeWeight(1.5)
        drawLine(point(0.5, 0), point(0.5, half))
        drawLine(point(0.5, half), point(0, half))
        stroke(theme.ink(0.5))
        drawLine(point(0, 0.5), point(fifth, 0.5))
        drawLine(point(fifth, 0.5), point(fifth, 0))
        noStrokeDash()

        noStroke()
        fill(theme.accent)
        drawCircle(center: point(0.5, half), radius: 5)
        fill(theme.ink)
        drawCircle(center: point(fifth, 0.5), radius: 5)

        fill(theme.muted)
        textSize(13)
        textAlign(.center, .top)
        drawText("light", r.x + r.width / 2, r.y + r.height + 8)

        // A key under the panel, so no note sits on the curve or the guides.
        textSize(14)
        textAlign(.left, .middle)
        fill(theme.accent)
        drawCircle(r.x + 6, r.y + r.height + 42, 5)
        drawText("half the light is stored as 0.74", r.x + 20, r.y + r.height + 42)
        fill(theme.ink)
        drawCircle(r.x + 6, r.y + r.height + 64, 5)
        drawText("a stored 0.5 is a fifth of the light", r.x + 20, r.y + r.height + 64)
    }

    func stripsPanel(_ r: Rectangle) {
        diagramFrame(r, title: "nine equal steps", theme: theme)
        let steps = 9
        let cell = (r.width - 40) / Double(steps)
        let top1 = r.y + 70
        let top2 = r.y + 200

        noStroke()
        for i in 0..<steps {
            let t = Double(i) / Double(steps - 1)
            let x = r.x + 20 + Double(i) * cell
            fill(Color(white: t))
            drawRect(x, top1, cell, 70)
            fill(Color(white: encoded(t)))
            drawRect(x, top2, cell, 70)
        }

        // An outline, so the white end shows on light paper and the black on dark.
        noFill()
        stroke(theme.border)
        strokeWeight(1)
        drawRect(r.x + 20, top1, cell * Double(steps), 70)
        drawRect(r.x + 20, top2, cell * Double(steps), 70)
        noStroke()

        fill(theme.ink)
        textSize(15)
        textAlign(.left, .bottom)
        drawText("of the stored number", r.x + 20, top1 - 8)
        drawText("of light", r.x + 20, top2 - 8)
    }
}
