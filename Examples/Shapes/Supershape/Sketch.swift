import Ollin

/// One supershape, morphing: the 2D Gielis superformula swept through its
/// parameter space by slow sines, so a single closed contour breathes through
/// star, flower, and gear-like forms. The outline is drawn twice, a translucent
/// fill under an ink line, over layered fading echoes of its recent shapes.
@main
final class Supershape: Sketch {
    override func draw() {
        background(Color(hex: 0x101418))

        let cx = width / 2, cy = height / 2
        let reach = Double(shortSide) * 0.34

        // Echoes: the same formula a few beats back, dimmer each step.
        for echo in stride(from: 4, through: 0, by: -1) {
            let t = time - Double(echo) * 0.35
            // Whole-number lobes: the superformula only closes in one turn
            // for integer m, so the lobe count steps while n1/n2/n3 morph.
            let m = (3 + (sin(t * 0.21) + 1) * 3.5).rounded()
            let outline = supershape(radius: reach,
                                     m: m,
                                     n1: 0.25 + (sin(t * 0.34) + 1) * 0.35,
                                     n2: 1.7 + sin(t * 0.27) * 1.2,
                                     n3: 1.7 + cos(t * 0.31) * 1.2)
            let age = Double(echo) / 4
            withState {
                translate(cx, cy)
                rotate(t * 0.05)
                if echo == 0 {
                    fill(Color(red: 0.36, green: 0.65, blue: 0.66, alpha: 0.35))
                    noStroke()
                    drawShape(Shape(contours: [outline]))
                    stroke(Color(hex: 0xEDE6D6))
                    strokeWeight(3.5 * scale)
                } else {
                    noFill()
                    stroke(Color(red: 0.36, green: 0.65, blue: 0.66,
                                 alpha: 0.25 * (1 - age)))
                    strokeWeight(1.5 * scale)
                }
                noFill()
                drawPolyline(outline.points, closed: true)
            }
        }
    }
}
