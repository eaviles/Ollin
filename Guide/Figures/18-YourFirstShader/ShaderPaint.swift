// figure: frame=90
//
// Guide figure (Chapter 18): a shader as paint. Three shapes drawn with ordinary
// calls under `fill(shader)` and `stroke(shader)`: a disk whose rings count
// inward from its edge (`info.distance`), a turned star striped in its own
// frame (`uv`), and a ribbon whose pulse travels its length while its ink
// thins toward the edges (`info.along` and `info.distance` on a stroke).
import Ollin

final class ShaderPaint: Sketch {
    override var canvasSize: CanvasSize { .size(880, 460) }

    private let rings = Shader("""
    float4 shade(float2 uv, ShaderInfo info) {
        float band = 0.5 + 0.5 * cos(-info.distance / 16.0 * 6.2831853 - info.time * 1.5);
        float3 deep = float3(0.09, 0.14, 0.42);
        float3 light = float3(0.98, 0.84, 0.46);
        return float4(mix(deep, light, smoothstep(0.35, 0.85, band)), 1.0);
    }
    """)

    private let stripes = Shader("""
    float4 shade(float2 uv, ShaderInfo info) {
        float s = fract((uv.x + uv.y) * 7.0 - info.time * 0.6);
        float3 a = float3(0.95, 0.33, 0.27);
        float3 b = float3(1.0, 0.92, 0.80);
        return float4(mix(a, b, step(0.5, s)), 1.0);
    }
    """)

    private let ribbon = Shader("""
    float4 shade(float2 uv, ShaderInfo info) {
        float pulse = 0.5 + 0.5 * cos((info.along - info.time * 0.25) * 6.2831853 * 3.0);
        float across = 1.0 - smoothstep(0.0, 14.0, abs(info.distance));
        float3 ink = mix(float3(0.16, 0.62, 0.58), float3(0.92, 0.98, 0.95), pulse);
        // Opaque, faded toward the ground by `across`: a translucent stroke would
        // composite twice where a tight bend folds its inner side over itself.
        return float4(mix(float3(0.08, 0.07, 0.10), ink, 0.3 + 0.7 * across), 1.0);
    }
    """)

    override func draw() {
        background(Color(hex: 0x14121A))

        noStroke()
        fill(rings)
        drawCircle(160, 230, 120)

        fill(stripes)
        withState {
            translate(440, 230)
            rotate(0.5)
            drawStar(0, 0, 118, 54, points: 5)
        }

        noFill()
        strokeWeight(40)
        strokeCap(.round)
        stroke(ribbon)
        // A bend no tighter than half the stroke's width, so the ribbon never
        // folds over itself on the inside of a turn.
        var points: [Vector2] = []
        for i in 0...48 {
            let t = Double(i) / 48
            points.append(Vector2(600 + t * 260, 230 + sin(t * .pi * 2 + .pi / 2) * 75))
        }
        drawPolyline(points)
    }
}
