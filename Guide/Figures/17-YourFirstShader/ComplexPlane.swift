// figure: frame=0 themed
//
// Guide figure (Chapter 17): the complex plane in a shader. Three tiles, each a
// user shader through the library's `complex` module: z squared, where the
// wheel goes round twice because multiplying adds the angles; the ratio of
// two points with the circles draw() works out laid over it, landing on the
// rulings; and e to the z ruled both ways.
import Ollin
import OllinDiagram

final class ComplexPlane: Sketch {
    override var canvasSize: CanvasSize { .size(880, 386) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }

    private let span = 3.0

    private func shader(_ function: String, shading: Int, strength: Double) -> Shader {
        Shader("""
        float4 shade(float2 uv, ShaderInfo info) {
            float2 z = complexPlane(uv, info.resolution, float2(0.0), \(span));
            float2 p = float2(param(info, 0), param(info, 1));
            float2 q = float2(param(info, 2), param(info, 3));
            float2 f = \(function);
            return float4(domainColor(f, \(shading), \(strength)), 1.0);
        }
        """, params: [Float(p.real), Float(p.imaginary), Float(q.real), Float(q.imaginary)],
        using: [.complex])
    }

    private let p = Complex(magnitude: 0.8, argument: 0.6)
    private let q = Complex(magnitude: 0.8, argument: 2.9)

    override func draw() {
        background(paper)

        let tile = 268, gap = 12.0
        let left = (width - Double(tile) * 3 - gap * 2) / 2

        let panels: [(String, Shader)] = [
            ("cmul(z, z): twice round", shader("cmul(z, z)", shading: 1, strength: 0.35)),
            ("cdiv(z - p, z - q) + circles", shader("cdiv(z - p, z - q)", shading: 2, strength: 0.7)),
            ("cexp(z): ruled both ways", shader("cexp(z)", shading: 2, strength: 0.7)),
        ]

        textFont(.system)
        for (index, panel) in panels.enumerated() {
            let x = left + Double(index) * (Double(tile) + gap)
            let rect = Rectangle(x: x, y: 20, width: Double(tile), height: Double(tile))
            drawImage(generate(panel.1, width: tile, height: tile).image, in: rect)

            if index == 1 { drawCircles(in: rect) }

            noStroke()
            fill(ink.withAlpha(0.62))
            textSize(15)
            textAlign(.center, .top)
            drawText(panel.0, rect.x + rect.width / 2, rect.y + rect.height + 8)
        }
    }

    /// The circles the ratio is made of, worked out with `Complex` and placed
    /// with the same framing the shader used: the circles of Apollonius where
    /// the size holds still, and the circles through both points where the
    /// direction does.
    private func drawCircles(in rect: Rectangle) {
        let scale = rect.width / span
        let place: (Complex) -> Vector2 = { z in
            Vector2(rect.x + rect.width / 2 + z.real * scale,
                    rect.y + rect.height / 2 - z.imaginary * scale)
        }
        withClip(rect) {
            noFill()
            stroke(Color(white: 1, alpha: 0.7))
            strokeWeight(1.5)
            let d = (p - q).magnitude
            for n in [-2, -1, 1, 2] {
                let k = pow(2.0, Double(n))
                let center = (p - k * k * q) / (1 - k * k)
                drawCircle(center: place(center), radius: k * d / abs(1 - k * k) * scale)
            }
            let middle = (p + q) / 2
            let across = Complex.i * (q - p) / d
            for step in 1 ... 5 {
                let theta = Double(step) * .pi / 6
                for sign in [1.0, -1.0] {
                    let center = middle + across * (sign * d / 2 * cos(theta) / sin(theta))
                    drawCircle(center: place(center), radius: d / (2 * sin(theta)) * scale)
                }
            }
            noStroke()
            fill(.white)
            textSize(14)
            textAlign(.center, .center)
            for (point, name) in [(p, "p"), (q, "q")] {
                let at = place(point)
                fill(.black)
                drawCircle(center: at, radius: 9)
                fill(.white)
                drawText(name, at.x, at.y + 1)
            }
        }
    }
}
