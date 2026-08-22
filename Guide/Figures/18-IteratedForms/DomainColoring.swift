// figure: frame=0
//
// Guide figure (Chapter 18): domain coloring. The color wheel itself, painted by
// the function that hands back its own input; a zero and a pole side by side,
// each turning the wheel once and in opposite directions; and the conformal
// ruling on tan z, where the two rulings cross in little squares.
import Ollin

final class DomainColoring: Sketch {
    override var canvasSize: CanvasSize { .size(880, 386) }

    override func draw() {
        background(Color(hex: 0xF7F5F1))

        let tile = 268, gap = 12.0
        let left = (width - Double(tile) * 3 - gap * 2) / 2

        let panels: [(String, Generator)] = [
            ("f(z) = z: color is direction",
             .domainColoring(.power(1), shading: .phase)),
            ("one zero, one pole",
             .domainColoring(.rational(zeros: [Vector2(-0.55, 0)], poles: [Vector2(0.55, 0)]),
                             shading: .phase, zoom: 1.35)),
            ("tan z, ruled both ways",
             .domainColoring(.tangent, shading: .conformal, zoom: 0.8)),
        ]

        textFont(.system)
        for (index, panel) in panels.enumerated() {
            let x = left + Double(index) * (Double(tile) + gap)
            let rect = Rectangle(x: x, y: 20, width: Double(tile), height: Double(tile))
            drawImage(generate(panel.1, width: tile, height: tile).image, in: rect)

            // Name the two features on the middle panel. The plane runs 3 units
            // across the tile with the imaginary axis up, so a point of the plane
            // lands at the middle plus its own offset, y negated.
            if index == 1 {
                let span = 3.0 / 1.35
                let place: (Vector2) -> Vector2 = { p in
                    Vector2(rect.x + rect.width / 2 + p.x / span * rect.width,
                            rect.y + rect.height / 2 - p.y / span * rect.height)
                }
                for (point, name) in [(Vector2(-0.55, 0), "zero"), (Vector2(0.55, 0), "pole")] {
                    let at = place(point)
                    noFill()
                    stroke(Color(white: 1, alpha: 0.85))
                    strokeWeight(2)
                    drawCircle(center: at, radius: 34)
                    noStroke()
                    fill(Color(white: 1, alpha: 0.9))
                    textSize(14)
                    textAlign(.center, .top)
                    drawText(name, at.x, at.y + 40)
                }
            }

            noStroke()
            fill(Color(hex: 0x2B2B2B, alpha: 0.62))
            textSize(16)
            textAlign(.center, .top)
            drawText(panel.0, rect.x + rect.width / 2, rect.y + rect.height + 8)
        }
    }
}
