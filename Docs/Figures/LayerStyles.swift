// figure: frame=0 themed
//
// Docs diagram (Drawing/LayerStyles.md): the six layer styles on one layer. Each
// panel draws the same disc, star, and letter into a layer and runs one style
// over it: an outline outside the edge, a drop shadow, an inner shadow, an outer
// glow, an inner glow, and a rounded bevel.
import Ollin
import OllinDiagram

final class LayerStyles: Sketch {
    override var canvasSize: CanvasSize { .size(880, 600) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    let face = OutlineFont(name: "AvenirNext-Heavy") ?? .systemBold

    override func draw() {
        background(theme.paper)
        let styles: [(String, Filter)] = [
            (".outline", .outline(width: 5, color: theme.ink)),
            (".dropShadow", .dropShadow(offset: Vector2(7, 9), radius: 9, color: Color(white: 0, alpha: 0.55))),
            (".innerShadow", .innerShadow(offset: Vector2(5, 6), radius: 5, color: Color(white: 0, alpha: 0.65))),
            (".outerGlow", .outerGlow(radius: 22, color: Color(hex: 0xFF4FA8))),
            (".innerGlow", .innerGlow(radius: 14, color: Color(hex: 0x8FF0FF))),
            (".bevel", .bevel(width: 11)),
        ]
        for (i, (title, style)) in styles.enumerated() {
            let panel = Rectangle(x: 40 + Double(i % 3) * 280, y: 56 + Double(i / 3) * 280,
                                  width: 240, height: 210)
            diagramFrame(panel, title: title, theme: theme)
            let layer = makeRenderTarget()
            withTarget(layer) {
                noStroke()
                fill(Color(hex: 0x2F6FD0))
                drawCircle(center: panel.point(u: 0.32, v: 0.36), radius: 46)
                fill(Color(hex: 0xE9A23B))
                drawStar(center: panel.point(u: 0.7, v: 0.34), outerRadius: 46, innerRadius: 21, points: 6)
                fill(Color(hex: 0xC8452F))
                textFont(face)
                textSize(78)
                textAlign(.center, .center)
                drawText("Aa", panel.point(u: 0.5, v: 0.76).x, panel.point(u: 0.5, v: 0.76).y)
            }
            drawImage(layer.filtered(style).image, 0, 0)
        }
    }
}
