import Ollin

/// `Filter.antialias`: smoothing the stair-steps in a layer a shader wrote pixel by
/// pixel. The renderer anti-aliases the shapes you draw, but a `generate(_:)` pattern,
/// a raymarched field, or a shader of your own writes a final color per pixel and
/// carries no coverage, so a hard edge inside one comes out as a staircase.
///
/// The scene is a spoke wheel, the classic test for this: every edge in it runs at a
/// different angle, and the shallow ones step worst. Drag the pointer to move the
/// split. Left of it is the layer as the shader wrote it, right of it the same layer
/// through the filter.
@main
final class Antialias_Example: Sketch {
    private let labelFont = OutlineFont.system

    @Param(0 ... 1, icon: "slider.horizontal.3") var amount = 1.0
    @Param(0.02 ... 0.4, icon: "circle.lefthalf.filled") var threshold = 0.125

    private let wheel = Shader("""
    float4 shade(float2 uv, ShaderInfo info) {
        float2 p = uv * 2.0 - 1.0;
        float r = length(p);
        float a = atan2(p.y, p.x) + info.time * 0.05;
        // Hard-edged spokes in a ring: no coverage, no softening, all staircase.
        float spokes = step(0.0, sin(a * 17.0)) * step(0.30, r) * step(r, 0.88);
        // One shallow band as well, the angle this pass helps most.
        float band = step(uv.y, 0.09 + uv.x * 0.05);
        float3 col = mix(float3(0.07, 0.09, 0.15), float3(0.97, 0.83, 0.42), spokes);
        col = mix(col, float3(0.85, 0.27, 0.36), band);
        return float4(col, 1.0);
    }
    """)

    override func draw() {
        background(Color(hex: 0x0B0E14))

        let raw = generate(wheel)
        let smoothed = raw.filtered(.antialias(amount: amount, threshold: threshold))

        // The pointer moves the split; it rests in the middle before anything moves.
        let split = mouseX > 0 ? min(max(mouseX, width * 0.1), width * 0.9) : width * 0.5

        drawImage(raw.image, 0, 0)
        withClip(Rectangle(x: split, y: 0, width: width - split, height: height)) {
            drawImage(smoothed.image, 0, 0)
        }

        stroke(Color(white: 1, alpha: 0.8)); strokeWeight(2)
        drawLine(split, 0, split, height)

        withState {
            noStroke()
            fill(Color(white: 1, alpha: 0.85))
            textFont(labelFont); textSize(20)
            textAlign(.left, .middle)
            drawText("as the shader wrote it", 22, height - 30)
            textAlign(.right, .middle)
            drawText("antialias", width - 22, height - 30)
        }
    }
}
