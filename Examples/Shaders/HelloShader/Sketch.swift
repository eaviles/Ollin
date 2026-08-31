import Ollin

// Inspired by Toby Howard (@tobyhoward), "x=cos(x)*cos(y), y=sin(x)*sin(y)"
//   https://x.com/tobyhoward/status/1529004242891153410 (24 May 2022)
// The inline plasma is a per-pixel trigonometric field mapped to a rainbow
// palette: an original Ollin interpretation built from the formula in the post,
// not a port of any source; credited here as a homage to the idea.

/// The smallest user-supplied shader, both ways in: a `shade(uv, info)`
/// function as an inline string (`Shader("...")`) on the left, and the same
/// contract loaded from a `.metal` file beside the sketch
/// (`Shader(resource:in:)`) on the right, the form for a shader too big to keep
/// in the Swift source. Each runs as a `generate(...)` source layer, colored
/// through `palette`, one of Ollin's built-in shader-library helpers, and
/// `info.time` drifts both, so they move on their own.
///
/// Under OllinLive both hot-reload: editing the string recompiles the sketch (a
/// typo is reported at this file's own line numbers), while saving
/// `ripple.metal` re-reads and recompiles just the shader, no swiftc pass, the
/// window never closing.
@main
final class HelloShader_Example: Sketch {
    private let labelFont = OutlineFont.system

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

    private let ripple = Shader(resource: "ripple", in: .module)

    override func draw() {
        background(Color(white: 0.06))

        // Two labeled tiles, each generated at its cell's own size.
        let space = width * 0.01
        let w = Int((width - space * 3) / 2), h = Int(height - space * 2)
        let tiles: [(String, RenderTarget)] = [
            ("inline: Shader(\"...\")", generate(plasma, width: w, height: h)),
            ("file: Shader(resource: \"ripple\")", generate(ripple, width: w, height: h)),
        ]

        textFont(labelFont)
        drawSheet(tiles, columns: 2) { layer, cell in
            drawImage(layer.image, in: cell)
        }
    }
}
