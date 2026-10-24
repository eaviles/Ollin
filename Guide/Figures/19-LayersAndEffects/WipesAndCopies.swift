// figure: frame=0 themed
// Guide figure (Chapter 19): wipes and copies. Two layers wiped halfway in
// three orders (a straight edge cut into shuffled bands, rings from a point, a
// checker of diamonds), then one petal copied around a ring, each copy turned to
// face out and moved round the hue wheel.
import Ollin
import OllinDiagram

final class WipesAndCopies: Sketch {
    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    override var canvasSize: CanvasSize { .size(880, 262) }

    private func scene(_ warm: Bool, _ side: Double) {
        noStroke()
        let rows = 10
        for row in 0 ..< rows {
            let t = Double(row) / Double(rows - 1)
            fill(warm ? Color(red: 0.86, green: 0.42 + 0.3 * t, blue: 0.26)
                      : Color(red: 0.14, green: 0.3 + 0.25 * t, blue: 0.56))
            drawRect(0, Double(row) * side / Double(rows), side, side / Double(rows))
        }
        fill(warm ? Color(hex: 0xF4E4A4) : Color(hex: 0xE6EEF6))
        drawCircle(side * 0.42, side * 0.48, side * 0.22)
    }

    override func draw() {
        background(theme.paper)
        let tile = 200.0, gap = 13.0
        let left = (width - tile * 4 - gap * 3) / 2
        let a = makeRenderTarget(width: Int(tile), height: Int(tile))
        let b = makeRenderTarget(width: Int(tile), height: Int(tile))
        withTarget(a) { scene(true, tile) }
        withTarget(b) { scene(false, tile) }
        let petal = makeRenderTarget(width: Int(tile), height: Int(tile))
        withTarget(petal) {
            background(Color(white: 0, alpha: 0))
            noStroke()
            fill(Color(hex: 0xE8A24A))
            drawEllipse(tile / 2, tile / 2 - 22, 11, 28)
        }
        let panels: [(String, RenderTarget)] = [
            ("bands(8).shuffled()", a.combined(with: b, .wipe(.directional(angle: 0.3).bands(8).shuffled(seed: 5),
                                                               progress: 0.5))),
            ("radial().bands(5)", a.combined(with: b, .wipe(.radial(center: Vector2(0.42, 0.48)).bands(5),
                                                             progress: 0.5))),
            ("checker().diamond()", a.combined(with: b, .wipe(.cells(columns: 6, rows: 6).checker().diamond(),
                                                                       progress: 0.5))),
            ("ring(facesOut: true)", petal.filtered(.repeated(.ring(radius: 0.15, facesOut: true),
                                                                          count: 10, scale: 0.96, hueShift: 0.3))),
        ]
        for (index, panel) in panels.enumerated() {
            let frame = Rectangle(x: left + Double(index) * (tile + gap), y: 14, width: tile, height: tile)
            noStroke()
            fill(Color(hex: 0x15171C))
            drawRect(frame)
            drawImage(panel.1.image, in: frame)
            fill(theme.ink(0.62))
            textFont(.systemMono)
            textSize(12.5)
            textAlign(.center, .top)
            drawText(panel.0, frame.x + frame.width / 2, frame.y + frame.height + 9)
        }
    }
}
