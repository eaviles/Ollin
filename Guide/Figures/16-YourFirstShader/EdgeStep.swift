// figure: frame=0
//
// Guide diagram (Chapter 16): smoothstep as an edge. The same disc, defined
// by distance from the center, drawn three ways: a hard step, a smoothstep
// a couple of pixels wide (a clean edge), and a smoothstep half the radius
// wide (a glow). One shader; only the edge width changes.
import Ollin

final class EdgeStep: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    func disc(_ softness: Double) -> Shader {
        Shader("""
        float4 shade(float2 uv, ShaderInfo info) {
            float2 p = uv - 0.5;
            float d = length(p);
            float edge = param(info, 0);
            float v = smoothstep(0.35, 0.35 - edge, d);
            float3 col = mix(float3(0.06, 0.09, 0.14), float3(1.0, 0.79, 0.29), v);
            return float4(col, 1.0);
        }
        """, params: [Float(softness)])
    }

    override func draw() {
        background(Color(hex: 0xF7F5F1))

        let labels = ["edge = 0  (a hard step)", "edge = 0.008  (a clean rim)",
                      "edge = 0.2  (a glow)"]
        let widths = [0.0001, 0.008, 0.2]
        let w = 265.0
        for i in 0 ..< 3 {
            let x = 22 + Double(i) * (w + 20)
            let panel = Rectangle(x: x, y: 80, width: w, height: w)
            drawImage(generate(disc(widths[i]), width: Int(w), height: Int(w)).image, in: panel)
            noStroke()
            fill(Color(hex: 0x2B2B2B, alpha: 0.6))
            textSize(16)
            textAlign(.center, .top)
            drawText(labels[i], panel.center.x, panel.y + panel.height + 12)
        }

        noStroke()
        fill(Color(hex: 0x2B2B2B))
        textSize(19)
        textAlign(.center, .top)
        drawText("smoothstep(0.35, 0.35 - edge, d): Chapter 3's curve, working as an edge",
                 width / 2, 480)
    }
}
