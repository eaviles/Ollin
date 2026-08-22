import Ollin

/// **Domain coloring**: a complex function painted over the plane it acts on.
/// Every pixel stands for one number, and the direction the function's answer
/// points picks its color off a wheel that wraps. Read the wheels: each zero
/// turns the palette through one full turn one way, each pole one turn the
/// other way, and the picture counts them for you.
///
/// The first tile places its own zeros and poles and swims them around; the
/// rest are functions worth knowing. `.conformal` shading rules the field in
/// both size and direction, so away from the interesting points it tiles into
/// little squares.
///
/// Try it: drag the zeros of the first tile by hand (`mouseX`, `mouseY` mapped
/// into the plane), or set every tile to `.phase` shading to see the color on
/// its own.
@main
final class DomainColoring_Example: Sketch {
    private let labelFont = OutlineFont.system

    override func draw() {
        background(Color(white: 0.06))

        let swim = time * 0.35
        let orbit = Vector2(cos(swim) * 0.35, sin(swim * 0.8) * 0.35)

        let gutter = width * 0.012
        let w = Int((width - gutter * 3) / 2), h = Int((height - gutter * 3) / 2)
        let tiles: [(Generator, String)] = [
            (.domainColoring(.rational(zeros: [Vector2(-0.55, -0.4) + orbit,
                                               Vector2(0.8, 0.5) - orbit],
                                       poles: [Vector2(0.62, -0.55),
                                               Vector2(-0.75, 0.6)]),
                             phase: time * 0.05),
             "two zeros, two poles"),
            (.domainColoring(.power(3), shading: .conformal), "z cubed"),
            (.domainColoring(.tangent, shading: .conformal, zoom: 0.8), "tan z"),
            (.domainColoring(.logarithm, shading: .modulus, zoom: 0.7), "log z"),
        ]

        for (i, tile) in tiles.enumerated() {
            let x = gutter + Double(i % 2) * (Double(w) + gutter)
            let y = gutter + Double(i / 2) * (Double(h) + gutter)
            drawImage(generate(tile.0, width: w, height: h).image,
                      in: Rectangle(x: x, y: y, width: Double(w), height: Double(h)))
            withState {
                noStroke()
                fill(Color(white: 0, alpha: 0.55))
                drawRect(x, y + Double(h) - 28, Double(w), 28)
                fill(.white)
                textFont(labelFont); textSize(15); textAlign(.left, .middle)
                drawText(tile.1, x + 10, y + Double(h) - 14)
            }
        }
    }
}
