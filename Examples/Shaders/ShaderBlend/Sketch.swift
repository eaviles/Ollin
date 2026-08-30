import Ollin

/// A user-supplied `Shader` as a two-input COMBINE. It reads two layers, the base
/// with `sample(info, uv)` and the aux with `sampleAux(info, uv)`, and blends them
/// with a shader-defined rule: an animated diagonal wipe whose seam ripples.
@main
final class ShaderBlend_Example: Sketch {
    private let blend = Shader("""
    float4 shade(float2 uv, ShaderInfo info) {
        float4 a = sample(info, uv);       // base layer
        float4 b = sampleAux(info, uv);    // aux layer
        float edge = uv.x + uv.y - 1.0 + sin(uv.y * 18.0 + info.time) * 0.06;
        float m = smoothstep(-0.05, 0.05, edge);
        return mix(a, b, m);
    }
    """)

    override func draw() {
        // Base: warm concentric rings.
        let warm = makeRenderTarget()
        withTarget(warm) {
            background(Color(hex: 0x2B1B12))
            noFill(); strokeWeight(14)
            for i in 0..<14 {
                stroke(Color(hex: i % 2 == 0 ? 0xFF8C42 : 0xFFD166))
                drawCircle(width / 2, height / 2, Double(i) * width / 26)
            }
        }
        // Aux: cool grid.
        let cool = makeRenderTarget()
        withTarget(cool) {
            background(Color(hex: 0x0E1B2A))
            stroke(Color(hex: 0x4CC9F0)); strokeWeight(6)
            let n = 12, step = width / Double(n)
            for i in 0...n {
                drawLine(Double(i) * step, 0, Double(i) * step, height)
                drawLine(0, Double(i) * step, width, Double(i) * step)
            }
        }
        drawImage(warm.combined(with: cool, .shader(blend)).image, 0, 0)
    }
}
