import Ollin

/// A user-supplied `Shader` as a one-input FILTER. Draw a scene into a layer, then
/// run a shader over it that reads the layer with `sample(info, uv)`: here a
/// horizontal wave (re-sampling at an offset uv) plus a posterize of the color.
@main
final class ShaderFilter_Example: Sketch {
    private let wave = Shader("""
    float4 shade(float2 uv, ShaderInfo info) {
        uv.x += sin(uv.y * 24.0 + info.time) * 0.02;   // ripple the lookup
        float4 c = sample(info, uv);                    // read the input layer
        c.rgb = floor(c.rgb * 6.0) / 6.0;               // posterize to 6 levels
        return c;
    }
    """)

    private let colors: [UInt32] = [0xFF5D73, 0xFFC857, 0x55D6BE, 0x8E7DBE, 0x3A86FF]

    override func draw() {
        // The scene to filter: a grid of bold dots on a dark ground.
        let layer = renderTarget()
        withTarget(layer) {
            background(Color(hex: 0x0E1116))
            noStroke()
            let n = 8
            let step = width / Double(n)
            for r in 0..<n {
                for c in 0..<n {
                    fill(Color(hex: colors[(r + c) % colors.count]))
                    drawCircle((Double(c) + 0.5) * step, (Double(r) + 0.5) * step, step * 0.34)
                }
            }
        }
        drawImage(layer.filtered(.shader(wave)).image, 0, 0)
    }
}
