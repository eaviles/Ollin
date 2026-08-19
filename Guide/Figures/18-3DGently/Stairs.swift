// figure: frame=0
//
// Guide listing (Chapter 18): transforms compose. Each slab inherits every
// move and turn made so far, so one repeated translate-and-rotate builds a
// spiral staircase.
import Ollin

final class Stairs: Sketch {
    override func draw() {
        background(Color(hex: 0x10141B))
        camera(.orbiting(target: Vector3(0, 4.4, 0), radius: 15,
                         azimuth: 0.7, elevation: 0.22, fieldOfView: .pi / 4))

        // The center post the treads wind around.
        withState {
            translate(0, 4.4, 0)
            fill(Color(white: 0.35))
            drawCylinder(radius: 0.22, height: 9.4)
        }

        for i in 0 ..< 26 {
            translate(0, 0.34, 0)          // each tread builds on the last:
            rotateY(0.34)                  // a step up and a turn
            withState {
                translate(1.25, 0, 0)      // out to the side, this tread only
                fill(Color(hue: 0.55 + Double(i) * 0.012, saturation: 0.5, brightness: 0.95))
                drawBox(width: 2.1, height: 0.15, depth: 0.85)
            }
        }
    }
}
