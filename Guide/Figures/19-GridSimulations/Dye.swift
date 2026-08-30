// figure: frame=150
//
// Guide listing (Chapter 19): the fluid. A brush orbits the center leaving
// dye whose hue drifts, and the same motion pushes the flow, so the color is
// stirred by the wake it paints.
import Ollin

final class Dye: Sketch {
    var fluid: SimField?

    override func draw() {
        background(Color(hex: 0x05070C))
        if fluid == nil { fluid = makeSimField(.fluid(curl: 34), scale: 0.5) }
        guard let fluid else { return }

        let a = time * 1.4
        let brush = Vector2(width / 2 + cos(a) * width * 0.27,
                            height / 2 + sin(a * 1.3) * height * 0.27)
        let push = Vector2(-sin(a), cos(a * 1.3)) * 7      // along the brush's motion
        withField(fluid, force: push) {
            noStroke()
            fill(Color(hue: time * 0.07, saturation: 0.85, brightness: 1))
            drawCircle(center: brush, radius: 15)
        }
        drawImage(fluid.filtered(.bloom(threshold: 0.4, amount: 1.1, radius: 14)).image, 0, 0)
    }
}
