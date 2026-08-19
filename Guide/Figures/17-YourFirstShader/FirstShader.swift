// figure: frame=0 probe
//
// Guide listing (Chapter 17): the first shader. Two coordinates in, one
// color out: red is u, green is v, and the whole canvas is the answer.
import Ollin

final class FirstShader: Sketch {
    let coordinates = Shader("""
    float4 shade(float2 uv, ShaderInfo info) {
        return float4(uv.x, uv.y, 0.6, 1.0);
    }
    """)

    override func draw() {
        drawImage(generate(coordinates).image, 0, 0)
    }
}
