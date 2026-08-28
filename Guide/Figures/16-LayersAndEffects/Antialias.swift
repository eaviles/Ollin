// figure: frame=0 themed
//
// Guide diagram (Chapter 16): post-process anti-aliasing. A shape written per
// pixel by a shader into a small layer, shown beside the same layer through
// `.antialias`. Both panels are magnified six times by reading the small layer
// at its own texel centers, so what you see is the real pixels rather than a
// smooth enlargement: the staircase on the left, the ramp on the right.
import Ollin
import OllinDiagram

final class Antialias: Sketch {
    override var canvasSize: CanvasSize { .size(880, 460) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }

    /// The small layer's side, in texels, and the panel's side on the page.
    let texels = 54.0
    let side = 324.0

    /// A disc and a shallow band, both written per pixel with no coverage at all.
    let scene = Shader("""
    float4 shade(float2 uv, ShaderInfo info) {
        float2 p = uv * 2.0 - 1.0;
        float disc = step(length(p), 0.66);
        float band = step(uv.y, 0.13 + uv.x * 0.17);
        float3 col = mix(float3(0.09, 0.11, 0.16), float3(0.96, 0.80, 0.35), disc);
        col = mix(col, float3(0.83, 0.28, 0.36), band);
        return float4(col, 1.0);
    }
    """)

    /// Magnify the second layer into one panel of this one, reading it at its own
    /// texel centers so every page pixel shows exactly one of its pixels.
    let magnifySource = """
    float4 shade(float2 uv, ShaderInfo info) {
        float2 origin = float2(param(info, 0), param(info, 1));
        float side = param(info, 2), texels = param(info, 3);
        float2 t = (uv * info.resolution - origin) / side;
        if (t.x < 0.0 || t.x > 1.0 || t.y < 0.0 || t.y > 1.0) return float4(0.0);
        float2 q = (floor(t * texels) + 0.5) / texels;
        return float4(sampleAux(info, q).rgb, 1.0);
    }
    """

    override func draw() {
        background(paper)

        let left = Rectangle(x: 88, y: 52, width: side, height: side)
        let right = Rectangle(x: 468, y: 52, width: side, height: side)

        let small = generate(scene, width: Int(texels), height: Int(texels))
        let smoothed = small.filtered(.antialias())

        drawImage(panel(small, at: left).image, 0, 0)
        drawImage(panel(smoothed, at: right).image, 0, 0)

        frame(left, title: "as the shader wrote it")
        frame(right, title: "filtered(.antialias())")

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("the step becomes a ramp, worked out from the picture alone",
                 width / 2, 404)
    }

    /// One magnified panel, as a page-sized layer that is clear everywhere else.
    /// The base layer is given a coat of paper first: a combine over a layer nothing
    /// has drawn into is skipped, and the pass would hand back that empty layer.
    func panel(_ layer: RenderTarget, at r: Rectangle) -> RenderTarget {
        let placed = Shader(magnifySource,
                            params: [Float(r.x), Float(r.y), Float(side), Float(texels)])
        let base = renderTarget()
        withTarget(base) { background(paper) }
        return base.combined(with: layer, .shader(placed))
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
