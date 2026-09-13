// figure: frame=0 themed
//
// Guide diagram (Chapter 26): temporal upscaling. On the left, why a frame
// rendered at half size can still rebuild the full canvas: each coarse render
// pixel covers four canvas pixels, the projection is nudged a different way
// each frame, and four frames land one sample in every canvas pixel. On the
// right, how much of the canvas each tier renders, as the square it draws
// inside the full one. A still cannot show the reconstruction itself, since an
// export never upscales; the mechanism is what a picture can carry.
import Ollin
import OllinDiagram

final class FewerPixels: Sketch {
    override var canvasSize: CanvasSize { .size(880, 470) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    override func draw() {
        background(theme.paper)
        textFont(.system)

        let side = 256.0
        let top = 84.0
        let left = Rectangle(x: 76, y: top, width: side, height: side)
        let right = Rectangle(x: 548, y: top, width: side, height: side)

        drawJitterGrid(in: left)
        diagramFrame(left, title: "half size: four frames sample every canvas pixel", theme: theme)
        drawLegend(under: left)
        drawText("thick lines: the pixels rendered; thin lines: the canvas",
                 left.x + left.width / 2, left.y + left.height + 34,
                 size: 13, color: theme.muted, align: .center, .top)

        drawTiers(in: right)
        diagramFrame(right, title: "what each tier renders", theme: theme)
        drawText("half a side is a quarter of the pixels, two thirds is four ninths,",
                 right.x + right.width / 2, right.y + right.height + 12,
                 size: 13, color: theme.muted, align: .center, .top)
        drawText("three quarters is nine sixteenths",
                 right.x + right.width / 2, right.y + right.height + 30,
                 size: 13, color: theme.muted, align: .center, .top)

        diagramCaption("render fewer pixels each frame; the jittered history supplies the rest",
                       at: 412, theme: theme)
    }

    /// The canvas as an eight-by-eight grid of thin lines, the half-size render
    /// as the four-by-four grid of thick ones, and in each render pixel the four
    /// places its sample lands over four frames, numbered once.
    private func drawJitterGrid(in r: Rectangle) {
        let fine = r.width / 8
        let coarse = r.width / 4

        noFill()
        stroke(theme.ink(0.18))
        strokeWeight(1)
        for i in 1..<8 {
            let d = Double(i) * fine
            drawLine(r.x + d, r.y, r.x + d, r.y + r.height)
            drawLine(r.x, r.y + d, r.x + r.width, r.y + d)
        }
        stroke(theme.ink)
        strokeWeight(2)
        for i in 1..<4 {
            let d = Double(i) * coarse
            drawLine(r.x + d, r.y, r.x + d, r.y + r.height)
            drawLine(r.x, r.y + d, r.x + r.width, r.y + d)
        }

        noStroke()
        let corners = [(0, 0), (1, 0), (0, 1), (1, 1)]
        for row in 0..<4 {
            for column in 0..<4 {
                for (k, corner) in corners.enumerated() {
                    let x = r.x + Double(column) * coarse + (Double(corner.0) + 0.5) * fine
                    let y = r.y + Double(row) * coarse + (Double(corner.1) + 0.5) * fine
                    fill(frameColors[k])
                    drawCircle(x, y, 5)
                }
            }
        }
    }

    /// One color per frame: the sample the render lands in each canvas pixel.
    private var frameColors: [Color] {
        [theme.accent, theme.accent(0.5), theme.ink(0.8), theme.ink(0.35)]
    }

    /// The four frames' dots, numbered, under the grid.
    private func drawLegend(under r: Rectangle) {
        let y = r.y + r.height + 18
        let spacing = 34.0
        let start = r.x + r.width / 2 - 24
        drawText("the sample from frame", start - 12, y, size: 13, color: theme.muted,
                 align: .right, .middle)
        noStroke()
        for k in 0..<4 {
            let x = start + Double(k) * spacing
            fill(frameColors[k])
            drawCircle(x, y, 5)
            drawText("\(k + 1)", x + 8, y, size: 13, color: theme.muted, align: .left, .middle)
        }
    }

    /// The full canvas, and inside it the square each tier renders, anchored at
    /// the same corner so the bands read as what each one gives up.
    private func drawTiers(in r: Rectangle) {
        let tiers: [(fraction: Double, name: String)] = [
            (1, "the canvas"),
            (3.0 / 4, ".detail, three quarters"),
            (2.0 / 3, ".default, two thirds"),
            (1.0 / 2, ".performance, half"),
        ]
        noStroke()
        for (index, tier) in tiers.enumerated() {
            let s = r.width * tier.fraction
            fill(index == 0 ? theme.card : theme.accent(0.11 + Double(index) * 0.13))
            drawRect(r.x, r.y, s, s)
        }
        noFill()
        stroke(theme.accent)
        strokeWeight(1.5)
        for tier in tiers.dropFirst() {
            let s = r.width * tier.fraction
            drawRect(r.x, r.y, s, s)
        }
        // Each label sits just under its own square's bottom edge, at the left,
        // where the band below it is the only thing it can cover.
        for tier in tiers {
            let s = r.width * tier.fraction
            let inside = tier.fraction == 1
            drawText(tier.name, r.x + 6, inside ? r.y + s - 6 : r.y + s + 4,
                     size: 13, color: theme.ink, align: .left, inside ? .bottom : .top)
        }
    }
}
