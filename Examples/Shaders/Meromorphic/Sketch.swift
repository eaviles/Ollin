import Ollin

// Inspired by Harley Turan, "Complex Number Visualization in GLSL"
//   https://hturan.com/writing/complex-numbers-glsl (April 2022)
// The picture is the article's last: a ratio of two cubic polynomials, its
// phase through a cosine palette with wild values, so the bands pile up near
// the poles. An original Ollin sketch written from that idea with the
// framework's own helpers (the polynomials are built from their roots, moving),
// not a port of the article's source; credited here as a homage.

/// A meromorphic function, painted by its phase.
///
/// A ratio of two polynomials is a function with zeros where the top vanishes
/// and poles where the bottom does. Here each polynomial is the product of
/// `(z - root)` over three roots, so the shader builds it with `cmul` and
/// divides with `cdiv`, and `draw()` places the six roots as `Complex` values
/// on slow orbits of their own. The color is the imaginary part of `clog` of
/// the ratio, the direction it points, through a cosine `palette`.
///
/// `wildness` scales the palette's frequency. At one the field reads as a
/// plain phase portrait, a wheel around every root. Higher, the palette turns
/// many times across the range and the bands pile up where the phase changes
/// fastest, around and between the poles. `marksRoots` draws a dot at each
/// zero and a ring at each pole.
@main
final class Meromorphic_Example: Sketch {
    /// How many times the palette turns across the range.
    @Param(0.5 ... 8) var wildness = 4.0
    /// The roots' orbits, in turns per minute.
    @Param(0 ... 6) var pace = 0.8
    /// Draw a dot at each zero and a ring at each pole.
    @Param var marksRoots = false
    /// The cosine palette, `base + swing * cos(tau * (frequency * t + offset))`,
    /// with `frequency` scaled by `wildness`.
    @Param(x: 0 ... 1, y: 0 ... 1, z: 0 ... 1) var base = Vector3(0.65, 0.48, 0.52)
    @Param(x: 0 ... 1, y: 0 ... 1, z: 0 ... 1) var swing = Vector3(0.33, 0.30, 0.34)
    @Param(x: 0 ... 2, y: 0 ... 2, z: 0 ... 2) var frequency = Vector3(1.0, 0.97, 0.94)
    @Param(x: 0 ... 1, y: 0 ... 1, z: 0 ... 1) var offset = Vector3(0.0, 0.10, 0.25)

    /// The plane spans three units across the canvas, the imaginary axis up.
    private let span = 3.0

    private let source = """
    float4 shade(float2 uv, ShaderInfo info) {
        float2 z = complexPlane(uv, info.resolution, float2(0.0), param(info, 12));
        float2 top = float2(1.0, 0.0), bottom = float2(1.0, 0.0);
        for (int i = 0; i < 3; i++) {
            top = cmul(top, z - float2(param(info, 2 * i), param(info, 2 * i + 1)));
            bottom = cmul(bottom, z - float2(param(info, 6 + 2 * i), param(info, 7 + 2 * i)));
        }
        float t = clog(cdiv(top, bottom)).y / 3.14159265;      // -1 ... 1
        float3 base = float3(param(info, 14), param(info, 15), param(info, 16));
        float3 swing = float3(param(info, 17), param(info, 18), param(info, 19));
        float3 frequency = float3(param(info, 20), param(info, 21), param(info, 22)) * param(info, 13);
        float3 offset = float3(param(info, 23), param(info, 24), param(info, 25));
        float3 col = palette(t, base, swing, frequency, offset);
        return float4(col, 1.0);
    }
    """

    /// Where each root's orbit is centered, and how far it swings.
    private let homes: [Complex] = [
        Complex(-0.9, 0.5), Complex(0.2, -0.8), Complex(0.7, 0.6),     // zeros
        Complex(-0.3, -0.2), Complex(1.0, -0.3), Complex(-0.8, -0.9),   // poles
    ]

    override func draw() {
        background(.black)

        // Every root swings around its home at its own phase, so the field
        // pours from one arrangement into the next rather than turning whole.
        let angle = time * pace * .tau / 60
        let roots = homes.enumerated().map { index, home in
            let sign: Double = index.isMultiple(of: 2) ? 1 : -1
            let phase = angle * sign + Double(index) * 1.1
            return home + Complex(magnitude: 0.35, argument: phase)
        }

        var params: [Float] = []
        for root in roots { params += [Float(root.real), Float(root.imaginary)] }
        params += [Float(span), Float(wildness)]
        for v in [base, swing, frequency, offset] { params += [Float(v.x), Float(v.y), Float(v.z)] }
        let picture = Shader(source, params: params, using: [.complex, .color])
        drawImage(generate(picture).image, 0, 0)

        guard marksRoots else { return }
        for (index, root) in roots.enumerated() {
            let at = place(root)
            if index < 3 {
                noStroke()
                fill(Color(white: 0.1, alpha: 0.9))
                drawCircle(center: at, radius: width * 0.008)
            } else {
                noFill()
                stroke(Color(white: 0.1, alpha: 0.9))
                strokeWeight(2)
                drawCircle(center: at, radius: width * 0.012)
            }
        }
    }

    /// The canvas point of a number of the plane, the same framing
    /// `complexPlane` gives the shader.
    private func place(_ z: Complex) -> Vector2 {
        let unit = min(width, height) / span
        return Vector2(width / 2 + z.real * unit, height / 2 - z.imaginary * unit)
    }
}
