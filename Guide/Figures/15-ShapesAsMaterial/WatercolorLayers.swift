// figure: frame=0 themed
//
// Guide diagram (Chapter 15): how a watercolor blob is built. The base
// outline, one translucent layer painted from it, and forty of them stacked.
// Nothing here is a texture or a blur; it is the same polygon deformed over
// and over and filled at a few percent opacity.
import Ollin
import OllinDiagram

final class WatercolorLayers: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }
    let pigment = Color(hex: 0x2B5D8A)

    override func draw() {
        background(paper)

        let panels = [Rectangle(x: 25, y: 62, width: 262, height: 300),
                      Rectangle(x: 309, y: 62, width: 262, height: 300),
                      Rectangle(x: 593, y: 62, width: 262, height: 300)]
        let titles = ["the polygon it starts from", "one layer at 4%",
                      "forty layers"]

        for (i, panel) in panels.enumerated() {
            frame(panel, title: titles[i])

            var rng = SplitMix64(seed: 12)
            let center = Vector2(panel.x + panel.width / 2,
                                 panel.y + panel.height / 2)
            // Same seed and same radius everywhere, so the ten-sided ring in
            // the first panel is literally what the other two grow from.
            let wash = Watercolor(around: center, radius: 92, variance: 28,
                                  rounds: i == 0 ? 0 : 7, using: &rng)

            switch i {
            case 0:
                noFill()
                stroke(pigment)
                strokeWeight(2)
                drawPolygon(wash.polygon)
            case 1:
                let layer = wash.layerShape(using: &rng)
                noStroke()
                fill(pigment.withAlpha(0.04))
                drawShape(layer)
                noFill()
                stroke(pigment.withAlpha(0.55))
                strokeWeight(1)
                drawShape(layer)
            default:
                noStroke()
                fill(pigment.withAlpha(0.04))
                for _ in 0 ..< 40 {
                    drawShape(wash.layerShape(using: &rng))
                }
            }
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("pigment is just one polygon, wobbled and stacked",
                 width / 2, 400)
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textSize(17)
        textAlign(.left, .middle)
        drawText(title, r.x + 2, r.y - 20)
    }
}
