// figure: frame=0
//
// Guide listing (Chapter 18): depth is real. Spheres placed at different
// depths shrink with distance and hide one another; a plane catches them.
import Ollin

final class DepthRow: Sketch {
    override func draw() {
        background(Color(hex: 0x10141B))
        cameraShowcase(target: Vector3(0, 0.4, -1), radius: 13,
                       elevation: 0.3, fieldOfView: .pi / 4)

        fill(Color(white: 0.75))
        drawPlane(width: 40, depth: 40)

        for i in 0 ..< 6 {
            withState {
                translate(Double(i) * 0.9 - 2.1, 0.7, 2.4 - Double(i) * 2.0)
                fill(Color(hue: 0.55 + Double(i) * 0.06, saturation: 0.55, brightness: 0.95))
                drawSphere(radius: 0.7)
            }
        }
    }
}
