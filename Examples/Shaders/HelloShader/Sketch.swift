import Ollin

// Inspired by Toby Howard (@tobyhoward), "x=cos(x)*cos(y), y=sin(x)*sin(y)"
//   https://x.com/tobyhoward/status/1529004242891153410 (24 May 2022)
// A per-pixel trigonometric field mapped to a rainbow palette. This is an
// original Ollin interpretation built from the formula in the post, not a port
// of any source; credited here as a homage to the idea.

/// The smallest user-supplied shader: a `shade(uv, info)` function run as a
/// fullscreen `generate(.shader(...))` source layer. The body evaluates a trig
/// field per pixel and colors it through `palette`, one of Ollin's built-in
/// shader-library helpers. `info.time` drifts it, so it moves on its own.
///
/// Edit the shader string under OllinLive and it hot-reloads with the sketch; a
/// typo is reported at this file's own line numbers, clickable in an IDE.
@main
final class HelloShader_Example: Sketch {
    private let plasma = Shader("""
    float4 shade(float2 uv, ShaderInfo info) {
        // Center and scale the coordinates, then evaluate the field. Keeping the two
        // components separate (rather than summing them, which collapses to cos(x-y))
        // gives a genuinely 2D field that tiles into a grid of blobs.
        float2 p = (uv * 2.0 - 1.0) * 6.0;
        float fx = cos(p.x) * cos(p.y);
        float fy = sin(p.x) * sin(p.y);
        float v = unipolar(sin((fx * fx + fy * fy) * 6.28318 + info.time));

        // A cosine gradient palette (iq), one of Ollin's shader-library helpers.
        float3 col = palette(v, float3(0.5), float3(0.5),
                             float3(1.0), float3(0.0, 0.33, 0.67));
        return float4(col, 1.0);
    }
    """)

    override func draw() {
        drawImage(generate(plasma).image, 0, 0)
    }
}
