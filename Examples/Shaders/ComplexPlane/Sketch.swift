import Ollin

// Inspired by Harley Turan, "Complex Number Visualization in GLSL"
//   https://hturan.com/writing/complex-numbers-glsl (April 2022)
// The picture is the one the article builds up to: two points move about the
// plane and every pixel is colored by the phase of (z - p) / (z - q). This is
// an original Ollin sketch written from that idea with the framework's own
// helpers, not a port of the article's source; credited here as a homage.

/// Complex numbers, both halves of the library at once.
///
/// The shader colors every pixel by the ratio `(z - p) / (z - q)` through the
/// shader library's `complex` module: `complexPlane` frames the layer as the
/// plane, `cdiv` divides, and `domainColor` turns the answer into a color,
/// its direction as the hue and its size and direction as two rulings.
///
/// `draw()` then works out, with the CPU `Complex` value, the two families of
/// circles that function is made of. Where the size of the ratio is constant
/// the points lie on the circles of Apollonius, nested around `p` and `q`, and
/// where its direction is constant they lie on the circles through both
/// points. Drawn over the layer, the circles land exactly on the rulings the
/// shader painted, which is the point: one arithmetic, on either side of the
/// GPU.
@main
final class ComplexPlane_Example: Sketch {
    /// How dark the rulings go.
    @Param(0 ... 1) var strength = 0.7
    /// The orbit's pace, in turns per minute.
    @Param(0 ... 6) var pace = 1.5
    /// Draw the circles the function is made of over the picture.
    @Param var drawsCircles = true

    private let labelFont = OutlineFont.system

    /// The plane spans three units across the canvas, the imaginary axis up.
    private let span = 3.0

    private let source = """
    float4 shade(float2 uv, ShaderInfo info) {
        float2 z = complexPlane(uv, info.resolution, float2(0.0), param(info, 4));
        float2 p = float2(param(info, 0), param(info, 1));
        float2 q = float2(param(info, 2), param(info, 3));
        float2 f = cdiv(z - p, z - q);
        return float4(domainColor(f, 2, param(info, 5)), 1.0);
    }
    """

    override func draw() {
        background(.black)

        // Two points orbiting the origin at different phases, so the pair
        // turns and breathes rather than only turning.
        let angle = time * pace * .tau / 60
        let p = Complex(magnitude: 0.8, argument: angle)
        let q = Complex(magnitude: 0.8, argument: angle + 2.3)

        // Compilation is cached by the source text, so new params each frame
        // cost nothing: only the numbers travel.
        let ratio = Shader(source, params: [Float(p.real), Float(p.imaginary),
                                            Float(q.real), Float(q.imaginary),
                                            Float(span), Float(strength)])
        drawImage(generate(ratio).image, 0, 0)

        guard drawsCircles else { return }
        noFill()
        stroke(Color(white: 1, alpha: 0.55))
        strokeWeight(1.5)

        // Where |f| holds still: the circle of Apollonius for the ratio k,
        // written in closed form with the two points as complex numbers. The
        // shader's size ruling steps at every doubling, so these are its edges.
        let d = (p - q).magnitude
        for n in [-3, -2, -1, 1, 2, 3] {
            let k = pow(2.0, Double(n))
            let center = (p - k * k * q) / (1 - k * k)
            let radius = k * d / abs(1 - k * k)
            drawCircle(center: place(center), radius: radius * unit)
        }

        // Where arg f holds still: the circles through both points. The
        // direction ruling has twelve sectors to the turn, so the edges sit
        // every thirty degrees; a circle carries an angle and its supplement,
        // and the two signs give the mirror pair.
        let middle = (p + q) / 2
        let across = Complex.i * (q - p) / d   // the perpendicular direction
        for step in 1 ... 5 {
            let theta = Double(step) * .pi / 6
            let radius = d / (2 * sin(theta))
            for sign in [1.0, -1.0] {
                let center = middle + across * (sign * d / 2 * cos(theta) / sin(theta))
                drawCircle(center: place(center), radius: radius * unit)
            }
        }
        // Zero degrees is the line through the points.
        let far = (q - p) / d * span * 2
        drawLine(place(p - far), place(q + far))

        // The two points themselves.
        noStroke()
        textFont(labelFont)
        textSize(width * 0.022)
        textAlign(.center, .center)
        for (point, name) in [(p, "p"), (q, "q")] {
            let at = place(point)
            fill(.black)
            drawCircle(center: at, radius: width * 0.012)
            fill(.white)
            drawText(name, at.x, at.y + width * 0.001)
        }
    }

    /// Canvas points per unit of the plane.
    private var unit: Double { min(width, height) / span }

    /// The canvas point of a number of the plane, the imaginary axis up, the
    /// same framing `complexPlane` gives the shader.
    private func place(_ z: Complex) -> Vector2 {
        Vector2(width / 2 + z.real * unit, height / 2 - z.imaginary * unit)
    }
}
