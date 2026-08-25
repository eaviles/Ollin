// figure: frame=0 themed
//
// Guide diagram (Chapter 17): the per-pixel mental model. The same little
// function is asked at every pixel: "you're at (u, v); what color are you?"
// Coarse on the left so each answer is visible, at full resolution on the
// right where the answers fuse into an image.
import Ollin

final class PixelGrid: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var faint: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.45) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }

    // The field both panels evaluate: a soft two-blob glow.
    func field(_ u: Double, _ v: Double) -> Color {
        let a = 1.0 - min(1, (Vector2(u, v) - Vector2(0.32, 0.4)).length / 0.42)
        let b = 1.0 - min(1, (Vector2(u, v) - Vector2(0.72, 0.68)).length / 0.5)
        let glow = max(0, a) + max(0, b) * 0.9
        return Color(hue: 0.58 - glow * 0.22, saturation: 0.75,
                     brightness: min(1, 0.12 + glow * 1.1))
    }

    override func draw() {
        background(paper)
        noStroke()

        // Left: a coarse pixel grid, one visible answer per cell.
        let panel = Rectangle(x: 40, y: 60, width: 360, height: 360)
        let cells = 12
        for cell in Grid(in: panel, columns: cells, rows: cells, gutter: 2).cells {
            let u = (Double(cell.column) + 0.5) / Double(cells)
            let v = (Double(cell.row) + 0.5) / Double(cells)
            fill(field(u, v))
            drawRect(cell.frame)
        }

        // Right: the same field, one answer per real pixel.
        let panelB = Rectangle(x: 480, y: 60, width: 360, height: 360)
        let n = 240
        for cell in Grid(in: panelB, columns: n, rows: n).cells {
            let u = (Double(cell.column) + 0.5) / Double(n)
            let v = (Double(cell.row) + 0.5) / Double(n)
            fill(field(u, v))
            drawRect(cell.frame)
        }

        noStroke()
        fill(faint)
        textSize(16)
        textAlign(.center, .top)
        drawText("every pixel asks the same question", panel.center.x, panel.y + panel.height + 12)
        drawText("asked at full resolution", panelB.center.x, panelB.y + panelB.height + 12)

        fill(ink)
        textSize(21)
        drawText("a shader is one small function, run at every pixel at once", width / 2, 495)
    }
}
