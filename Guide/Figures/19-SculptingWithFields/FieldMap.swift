// figure: frame=0
//
// Guide diagram (Chapter 19): a signed-distance field, seen whole. Every
// point knows how far the nearest surface is; the sign says which side. The
// bands are lines of equal distance, and the bold line is distance zero: the
// shape itself. Rendered by a per-pixel shader over the shared sd helpers.
import Ollin

final class FieldMap: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let field = Shader("""
    float4 shade(float2 uv, ShaderInfo info) {
        float2 p = (uv - 0.5) * float2(info.resolution.x / info.resolution.y, 1.0) * 2.3;
        float d1 = length(p - float2(-0.42, 0.02)) - 0.34;
        float d2 = sdRoundBox(p - float2(0.36, -0.04), float2(0.33, 0.24), 0.08);
        float d = smin(d1, d2, 0.28);

        float3 paper = float3(0.969, 0.961, 0.945);
        float3 cool = float3(0.62, 0.70, 0.78);
        float3 warm = float3(0.894, 0.341, 0.180);

        float bands = 0.5 + 0.5 * cos(d * 55.0);
        float3 color;
        if (d > 0.0) {
            color = mix(paper, cool, 0.35 * bands * exp(-d * 1.6));
        } else {
            color = mix(warm, float3(1.0, 0.86, 0.78), 0.4 * bands);
        }
        float contour = 1.0 - smoothstep(0.006, 0.016, abs(d));
        color = mix(color, float3(0.17, 0.17, 0.17), contour);
        return float4(color, 1.0);
    }
    """)

    override func draw() {
        drawImage(generate(.shader(field)).image, 0, 0)

        let ink = Color(hex: 0x2B2B2B)
        fill(ink)
        textSize(26)
        textAlign(.left, .middle)
        drawText("outside: distance > 0", 40, 60)
        drawText("each band is one step farther", 40, 96)
        textAlign(.center, .middle)
        fill(.white)
        drawText("inside:", 330, 258)
        drawText("distance < 0", 330, 292)
        fill(ink)
        drawText("the surface: distance = 0", 628, 408)
    }
}
