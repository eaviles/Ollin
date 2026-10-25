// figure: frame=0 themed
// Guide figure (Chapter 22): layer styles. One word and one disc drawn into a
// layer the ordinary way, then given an edge three ways: an outline, a bevel
// with a glow held inside it, and a drop shadow with an inner shadow.
import Ollin
import OllinDiagram

final class LayerStyles: Sketch {
    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    override var canvasSize: CanvasSize { .size(880, 386) }

    override func draw() {
        background(theme.paper)
        let tile = 268.0, gap = 12.0
        let left = (width - tile * 3 - gap * 2) / 2
        let labels = ["outline", "bevel and inner glow", "drop and inner shadow"]
        // The light sits up and to the left, so the bevel's highlights face it
        // and both shadows fall away from it.
        let light = -.pi * 0.75
        let away = Vector2(-cos(light), -sin(light))
        for index in 0 ..< 3 {
            let x = left + Double(index) * (tile + gap)
            let frame = Rectangle(x: x, y: 20, width: tile, height: tile)
            // The same marks in every panel: a heavy word and a disc, so the
            // styles read on lettering and on a plain shape side by side.
            let marks = makeRenderTarget(width: Int(tile), height: Int(tile))
            withTarget(marks) {
                background(Color(white: 0, alpha: 0))
                noStroke()
                fill(Color(hex: 0x2F6FD0))
                drawCircle(tile * 0.74, tile * 0.25, tile * 0.12)
                fill(Color(hex: 0xC8452F))
                textFont(OutlineFont(name: "AvenirNext-Heavy") ?? .systemBold)
                textSize(tile * 0.33)
                textAlign(.center, .center)
                drawText("edge", tile * 0.48, tile * 0.64)
            }
            let styled: RenderTarget
            switch index {
            case 0:
                styled = marks
                    .filtered(.outline(width: 4, color: Color(hex: 0x9C2F3C), align: .inside))
                    .filtered(.outline(width: 8, color: Color(hex: 0x1C1A24)))
            case 1:
                styled = marks
                    .filtered(.bevel(width: 14, angle: light))
                    .filtered(.innerGlow(radius: 12, color: Color(white: 1, alpha: 0.4)))
            default:
                styled = marks
                    .filtered(.innerShadow(offset: away * 6, radius: 6,
                                           color: Color(white: 0, alpha: 0.6)))
                    .filtered(.dropShadow(offset: away * 14, radius: 12,
                                          color: Color(white: 0, alpha: 0.45)))
            }
            noStroke()
            fill(Color(hex: 0xD9D4CA))
            drawRect(frame)
            drawImage(styled.image, in: frame)
            fill(theme.ink(0.62))
            textFont(.system)
            textSize(16)
            textAlign(.center, .top)
            drawText(labels[index], frame.x + frame.width / 2, frame.y + frame.height + 8)
        }
    }
}
