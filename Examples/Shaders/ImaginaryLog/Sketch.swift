import Ollin

// Inspired by Harley Turan, "Complex Number Visualization in GLSL"
//   https://hturan.com/writing/complex-numbers-glsl (April 2022)
// The picture is the article's first: the imaginary part of the logarithm of
// (z - p) / (z - q), two points turning, through a cosine palette that never
// completes a cycle, so the branch cut shows as a soft seam. An original Ollin
// sketch written from that idea with the framework's own helpers, not a port
// of the article's source; credited here as a homage.

/// The imaginary part of a logarithm, as a picture.
///
/// `clog(f)` is `(log|f|, arg f)`, so its imaginary part is the direction `f`
/// points, between minus pi and pi. For the ratio `(z - p) / (z - q)` that is
/// the angle the segment from `q` to `p` subtends at `z`: a smooth field
/// everywhere except along the segment itself, where it jumps from one end of
/// the range to the other. Fed to a cosine `palette` whose period is longer
/// than the range, the jump shows as a seam between the two points, and
/// everything else fades. The seam is the branch cut of the logarithm, drawn.
///
/// `turns` is how far the palette goes round across the range: below one the
/// seam stays, at a whole number it closes and the picture becomes a plain
/// phase portrait. `draw()` marks the same segment with `Complex` when asked,
/// the CPU half of the same arithmetic.
@main
final class ImaginaryLog_Example: Sketch {
    /// How far the palette turns across the range; below 1 the seam shows.
    @Param(0.1 ... 3) var turns = 0.3
    /// The points' orbit, in turns per minute.
    @Param(0 ... 6) var pace = 3.0
    /// Draw the segment the seam sits on, and the two points.
    @Param var marksTheCut = false
    /// The cosine palette, `base + swing * cos(tau * (frequency * t + offset))`:
    /// four vectors to alter endlessly.
    @Param(x: 0 ... 1, y: 0 ... 1, z: 0 ... 1) var base = Vector3(0.60, 0.62, 0.66)
    @Param(x: 0 ... 1, y: 0 ... 1, z: 0 ... 1) var swing = Vector3(0.30, 0.22, 0.24)
    @Param(x: 0 ... 2, y: 0 ... 2, z: 0 ... 2) var frequency = Vector3(0.80, 0.80, 0.60)
    @Param(x: 0 ... 1, y: 0 ... 1, z: 0 ... 1) var offset = Vector3(0.55, 0.30, 0.28)

    /// The plane spans three units across the canvas, the imaginary axis up.
    private let span = 3.0

    private let source = """
    float4 shade(float2 uv, ShaderInfo info) {
        float2 z = complexPlane(uv, info.resolution, float2(0.0), param(info, 4));
        float2 p = float2(param(info, 0), param(info, 1));
        float2 q = float2(param(info, 2), param(info, 3));
        float t = clog(cdiv(z - p, z - q)).y / 3.14159265;      // -1 ... 1
        float3 base = float3(param(info, 6), param(info, 7), param(info, 8));
        float3 swing = float3(param(info, 9), param(info, 10), param(info, 11));
        float3 frequency = float3(param(info, 12), param(info, 13), param(info, 14));
        float3 offset = float3(param(info, 15), param(info, 16), param(info, 17));
        float3 col = palette(t * param(info, 5), base, swing, frequency, offset);
        return float4(col, 1.0);
    }
    """

    override func draw() {
        background(.black)

        // Two points opposite each other on a circle, turning.
        let angle = time * pace * .tau / 60
        let p = Complex(magnitude: 0.6, argument: angle)
        let q = -p

        var params: [Float] = [Float(p.real), Float(p.imaginary), Float(q.real), Float(q.imaginary),
                               Float(span), Float(turns)]
        for v in [base, swing, frequency, offset] { params += [Float(v.x), Float(v.y), Float(v.z)] }
        let picture = Shader(source, params: params, using: [.complex, .color])
        drawImage(generate(picture).image, 0, 0)

        guard marksTheCut else { return }
        // The seam is exactly the segment between the points: the one place
        // the angle subtended is a straight angle and the sign flips.
        stroke(Color(white: 0.1, alpha: 0.7))
        strokeWeight(1.5)
        drawLine(place(p), place(q))
        noStroke()
        fill(Color(white: 0.1, alpha: 0.9))
        for point in [p, q] {
            drawCircle(center: place(point), radius: width * 0.008)
        }
    }

    /// The canvas point of a number of the plane, the same framing
    /// `complexPlane` gives the shader.
    private func place(_ z: Complex) -> Vector2 {
        let unit = min(width, height) / span
        return Vector2(width / 2 + z.real * unit, height / 2 - z.imaginary * unit)
    }
}
