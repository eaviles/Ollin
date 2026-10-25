// figure: frame=0 themed
//
// Guide figure (Chapter 43): the four line textures as a pen would draw them,
// each the geometry its emitter hands back, stroked in one ink. Wood grain
// traced over a knot, frost grown along a circle, crackle grown in a square
// with one crease, and three ikat stripes with their stepped edges.
import Ollin
import OllinDiagram

final class LineTextures: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    override func draw() {
        background(theme.paper)
        let ink = theme.ink
        let side = 192.0, gap = 12.0, top = 48.0
        let left = (width - side * 4 - gap * 3) / 2
        let panels = (0 ..< 4).map { Rectangle(x: left + Double($0) * (side + gap), y: top, width: side, height: side) }
        strokeCap(.round)
        strokeJoin(.round)

        // Wood grain: strokes dark on the rings, light between them.
        let knot = WoodGrain.Knot(center: panels[0].center + Vector2(20, 24), radius: 17, height: 3.5)
        let grain = WoodGrain.trace(in: panels[0], direction: 0.1, spacing: 4, knots: [knot], ringSpacing: 24,
                                    wobble: 0.3, seed: 3)
        noFill()
        for line in grain.strokes {
            stroke(ink.withAlpha(0.3 + 0.7 * line.tone))
            strokeWeight(0.5 + 0.7 * line.tone)
            if line.isClosed { drawPolygon(line.points) } else { drawPolyline(line.points) }
        }

        // Frost: needles both ways off a circle.
        let frost = Frost.grow(along: Circle(center: panels[1].center, radius: 46).contour, spacing: 5,
                               length: 34, clump: 0.6, barbSpacing: 4, side: .both, seed: 2)
        stroke(ink)
        strokeWeight(0.9)
        for line in frost.strokes { drawPolyline(line) }

        // Crackle: veins in a square, crowding along one crease.
        let wax = Rectangle(x: panels[2].x + 10, y: panels[2].y + 10, width: side - 20, height: side - 20)
        let crease = [Vector2(wax.x + 20, wax.y + 30), Vector2(wax.x + wax.width - 24, wax.y + wax.height - 20)]
        let crackle = Crackle.grow(in: wax, spacing: 20, creases: [crease], seed: 5)
        stroke(theme.ink(0.3))
        strokeWeight(1)
        drawRect(wax)
        stroke(ink)
        strokeWeight(1.1)
        for line in crackle.lines { drawPolyline(line) }

        // Ikat: three stripes, filled, with their stepped edges stroked.
        let cloth = Rectangle(x: panels[3].x + 10, y: panels[3].y + 10, width: side - 20, height: side - 20)
        let stripes = Ikat.stripes(in: cloth, count: 3, bundle: 6, bleed: 10, seed: 4)
        for (i, stripe) in stripes.stripes.enumerated() {
            noStroke()
            fill(i == 1 ? theme.ink(0.45) : theme.ink(0.8))
            drawShape(stripe.shape)
            noFill()
            stroke(ink)
            strokeWeight(0.8)
            for edge in stripe.edges { drawPolyline(edge) }
        }

        let titles = ["WoodGrain.trace", "Frost.grow", "Crackle.grow", "Ikat.stripes"]
        for (panel, title) in zip(panels, titles) { diagramFrame(panel, title: title, theme: theme) }
        diagramCaption("four textures as lines a pen can draw, each from a seed", at: 262, theme: theme)
    }
}
