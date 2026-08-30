// figure: frame=0 themed
//
// Guide figure (Chapter 16): light a flat sketch works out for itself. What was drawn,
// the light that reaches it, and the same light with one bounce off the walls.
import Ollin
import OllinDiagram

final class LightField: Sketch {
    override var canvasSize: CanvasSize { .size(880, 386) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    let walls = Color(hex: 0x2B3138)
    let ink = Color(hex: 0xC8503C)
    let sea = Color(hex: 0x3F8F6B)
    let sun = Color(hex: 0xE0C25C)

    override func draw() {
        background(theme.paper)

        let tile = 268.0, gap = 12.0
        let left = (width - tile * 3 - gap * 2) / 2
        let labels = ["what was drawn", "the light", "with one bounce"]

        textFont(.system)
        for index in 0 ..< 3 {
            let x = left + Double(index) * (tile + gap)
            let frame = Rectangle(x: x, y: 20, width: tile, height: tile)

            // The scene: what light meets. The layer starts empty, and empty is where
            // light travels.
            let scene = makeRenderTarget(width: Int(tile), height: Int(tile))
            withTarget(scene) {
                noStroke()
                fill(walls)
                drawRect(corner: Vector2(tile * 0.06, tile * 0.06),
                         width: tile * 0.88, height: tile * 0.05)
                drawRect(corner: Vector2(tile * 0.06, tile * 0.89),
                         width: tile * 0.88, height: tile * 0.05)
                drawRect(corner: Vector2(tile * 0.06, tile * 0.06),
                         width: tile * 0.05, height: tile * 0.88)
                fill(sea)
                drawRect(corner: Vector2(tile * 0.89, tile * 0.06),
                         width: tile * 0.05, height: tile * 0.88)
                fill(ink)
                drawRect(corner: Vector2(tile * 0.18, tile * 0.66),
                         width: tile * 0.34, height: tile * 0.05)
                fill(walls)
                for tooth in 0 ..< 4 {
                    drawRect(corner: Vector2(tile * (0.24 + Double(tooth) * 0.15), tile * 0.4),
                             width: tile * 0.05, height: tile * 0.13)
                }
                fill(sun)
                drawCircle(tile * 0.72, tile * 0.76, tile * 0.08)
            }

            // The lamps: what gives light off.
            let lamps = makeRenderTarget(width: Int(tile), height: Int(tile))
            withTarget(lamps) {
                noStroke()
                fill(.white)
                drawCircle(tile * 0.5, tile * 0.22, tile * 0.035)
            }

            noStroke()
            fill(Color(hex: 0x0A0C10))
            drawRect(frame)

            switch index {
            case 0:
                drawImage(lamps.image, in: frame)
                drawImage(scene.image, in: frame)
            default:
                let lit = scene.combined(with: lamps,
                                         .light(brightness: 5, bounces: index == 1 ? 0 : 1,
                                                quality: .detail))
                drawImage(lit.image, in: frame)
            }

            fill(theme.ink(0.62))
            textSize(16)
            textAlign(.center, .top)
            drawText(labels[index], frame.x + frame.width / 2, frame.y + frame.height + 8)
        }
    }
}
