// figure: frame=150
//
// Guide figure (Chapter 19): a simulation of one's own. A heat plate run by a
// kernel the sketch writes: each cell blends toward its four neighbors and cools
// a little, the edge is clamped (an insulated plate, so the heat stays in), an
// inject kernel adds a hot disc where a scripted brush lands, and the state
// keeps the heat's slope in its first two channels so `.arrows` can draw where
// the heat flows. Recolored through a magma ramp.
import Ollin

final class OwnRule: Sketch {
    var plate: SimField!

    let step = Shader("""
    float4 shade(float2 uv, ShaderInfo info) {
        float here = cell(info).z;
        float left = cell(info, -1, 0).z, right = cell(info, 1, 0).z;
        float up = cell(info, 0, -1).z, down = cell(info, 0, 1).z;
        float heat = mix(here, (left + right + up + down) * 0.25, 0.5) * 0.997;
        float2 flow = float2(left - right, up - down);      // heat runs down its slope
        return float4(flow, heat, 1.0);
    }
    """)

    let inject = Shader("""
    float4 shade(float2 uv, ShaderInfo info) {
        float4 me = cell(info);
        float4 m = mark(info);
        return float4(me.xy, me.z + m.a * 1.5, 1.0);        // a mark adds heat, never replaces it
    }
    """)

    override func setup() {
        plate = makeSimField(.shader(step, inject: inject, substeps: 4), scale: 0.5, edge: .clamped)
    }

    override func draw() {
        background(.black)
        withField(plate) {
            noStroke(); fill(.white)
            let t = Double(frameCount)
            if frameCount < 130 {
                drawCircle(140 + t * 6, 540 + sin(t * 0.09) * 260, 30)   // the brush, crossing once
            }
        }
        let heat = Shader("""
        float4 shade(float2 uv, ShaderInfo info) {
            float h = clamp(sampleRaw(info, uv).z, 0.0, 1.0);
            return float4(h, h, h, 1.0);
        }
        """)
        drawImage(plate.filtered(.shader(heat)).filtered(.gradientMap(.magma)).image, 0, 0)
        drawImage(plate.filtered(.arrows(spacing: 24, scale: 400, color: Color(white: 1, alpha: 0.7),
                                         width: 1.5)).image, 0, 0)
    }
}
