// figure: frame=0 themed
//
// Guide diagram (Chapter 23): what erosion does to generated terrain. The
// same diamond-square field as a heightmap, then after rain has run over it,
// then after gravity settles the slopes that stand too steep. Brighter is
// higher.
import Ollin
import OllinDiagram

final class Erosion: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }

    var stages: [Image] = []

    override func setup() {
        let raw = Heightfield.diamondSquare(size: 257, roughness: 0.55, seed: 7)
        let rained = raw.eroded(.hydraulic(drops: 50_000), seed: 7)
        let settled = rained.eroded(.thermal(talus: 0.012, iterations: 30))
        stages = [raw.image(), rained.image(), settled.image()]
    }

    override func draw() {
        background(paper)

        let titles = ["diamond-square", "after rain", "after gravity"]
        for (i, picture) in stages.enumerated() {
            let panel = Rectangle(x: 25 + Double(i) * 284, y: 66,
                                  width: 262, height: 262)
            drawImage(picture, in: panel)
            frame(panel, title: titles[i])
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("noise becomes landscape when water has had a turn at it",
                 width / 2, 364)
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
        drawText(title, r.x, r.y - 20)
    }
}
