// figure: frame=0 themed
//
// Guide figure (Chapter 16): a measured distance field. The marks on their own, how far
// every pixel is from the nearest one, and which way that nearest one lies.
import Ollin
import OllinDiagram

final class MeasuredField: Sketch {
    override var canvasSize: CanvasSize { .size(880, 386) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }

    let ink = Color(hex: 0xE8734A)
    let sea = Color(hex: 0x49B0A5)
    let sun = Color(hex: 0xE0C25C)

    override func draw() {
        background(paper)

        let tile = 268.0, gap = 12.0
        let left = (width - tile * 3 - gap * 2) / 2
        let labels = ["the marks", "how far", "which way"]

        textFont(.system)
        for index in 0 ..< 3 {
            let x = left + Double(index) * (tile + gap)
            let frame = Rectangle(x: x, y: 20, width: tile, height: tile)

            let marks = makeRenderTarget(width: Int(tile), height: Int(tile))
            withTarget(marks) {
                background(Color(white: 0, alpha: 0))
                noStroke()
                fill(ink)
                drawCircle(tile * 0.27, tile * 0.28, tile * 0.11)
                fill(sun)
                drawRect(corner: Vector2(tile * 0.64, tile * 0.14),
                         width: tile * 0.19, height: tile * 0.19)
                noFill()
                stroke(sea)
                strokeWeight(7)
                drawPolyline([Vector2(tile * 0.09, tile * 0.82), Vector2(tile * 0.37, tile * 0.68),
                              Vector2(tile * 0.63, tile * 0.85), Vector2(tile * 0.9, tile * 0.64)])
            }

            noStroke()
            fill(Color(hex: 0x101820))
            drawRect(frame)

            let field = marks.filtered(.distanceField())
            switch index {
            case 0:
                drawImage(marks.image, in: frame)
            case 1:
                drawImage(field.filtered(.fieldMap(bands, from: 0, to: 34,
                                                   repeating: true)).image, in: frame)
            default:
                drawImage(field.combined(with: marks,
                                         .shader(Shader(MeasuredField.nearest))).image, in: frame)
                drawImage(marks.image, in: frame)
            }

            fill(theme.ink(0.62))
            textSize(16)
            textAlign(.center, .top)
            drawText(labels[index], frame.x + frame.width / 2, frame.y + frame.height + 8)
        }
    }

    /// Dark at every edge, fading out, repeated: the contour lines of a map.
    var bands: Ramp {
        Ramp(stops: [(0, Color(hex: 0xF3EDE2)), (0.07, Color(hex: 0x2B3947)),
                     (0.16, Color(hex: 0xF3EDE2)), (1, Color(hex: 0xAEBAC6))])
    }

    /// Walk to the nearest edge, step a little past it, and bring that color back.
    static let nearest = """
    float4 shade(float2 uv, ShaderInfo info) {
        float4 field = sampleRaw(info, uv);
        float2 here = uv * info.resolution;
        float2 inside = here + field.gb * (abs(field.r) + 4.0 * sign(field.r));
        return float4(sampleAux(info, inside / info.resolution).rgb * 0.6, 1.0);
    }
    """
}
