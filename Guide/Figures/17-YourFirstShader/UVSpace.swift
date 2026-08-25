// figure: frame=0 themed
//
// Guide diagram (Chapter 17): uv space. The first shader's own output (red
// grows with u, green with v), annotated with the corners and center so the
// coordinate system is readable at a glance.
import Ollin
import OllinDiagram

final class UVSpace: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }

    let gradient = Shader("""
    float4 shade(float2 uv, ShaderInfo info) {
        return float4(uv.x, uv.y, 0.6, 1.0);
    }
    """)

    override func draw() {
        background(paper)

        let panel = Rectangle(x: 220, y: 55, width: 440, height: 380)
        drawImage(generate(gradient, width: Int(panel.width), height: Int(panel.height)).image,
                  in: panel)
        noFill()
        stroke(ink.withAlpha(0.4))
        strokeWeight(1.5)
        drawRect(panel)

        noStroke()
        fill(ink)
        textSize(17)
        textAlign(.right, .middle)
        drawText("uv = (0, 0)", panel.x - 12, panel.y + 8)
        textAlign(.left, .middle)
        drawText("uv = (1, 0)", panel.x + panel.width + 12, panel.y + 8)
        textAlign(.right, .middle)
        drawText("uv = (0, 1)", panel.x - 12, panel.y + panel.height - 8)
        textAlign(.left, .middle)
        drawText("uv = (1, 1)", panel.x + panel.width + 12, panel.y + panel.height - 8)

        fill(.white)
        drawCircle(center: panel.center, radius: 5)
        textAlign(.center, .top)
        drawText("(0.5, 0.5)", panel.center.x, panel.center.y + 12)

        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("uv runs 0 to 1 across the layer, top-left origin, like the canvas", width / 2, 495)
    }
}
