// figure: frame=0
//
// Figure for Docs/3D/Lines.md: lines through the camera. A floor grid and the
// axes; a sphere with a knot of line weaving in front of it and behind it,
// colored point by point; a straight white line passing behind the sphere,
// hidden where the sphere covers it; and two lines running back across the
// floor, the left one a weight on screen that holds its width, the right one a
// weight in world units that thins as it recedes.
import Ollin

final class Lines3D: Sketch {
    override var canvasSize: CanvasSize { .size(880, 400) }

    override func draw() {
        background(Color(hex: 0x0B0C12))
        camera(.perspective(eye: Vector3(0.6, 2.2, 5.4), target: Vector3(0, 0.75, 0), fieldOfView: .pi / 5.2))
        directionalLight(.white, direction: Vector3(-0.4, -0.7, -0.6), intensity: 1.1)
        ambientLight(Color(white: 0.3))

        stroke(Color(hex: 0x323A4C))
        strokeWeight(1)
        drawGrid(size: 14, divisions: 14)
        strokeWeight(2.5)
        drawAxes(length: 1.4)

        fill(Color(hex: 0x2C4C80))
        specular(0.35); specularSharpness(40)
        withState { translate(0, 0.9, 0); drawSphere(radius: 0.75, segments: 64, rings: 32) }

        // A (2, 3) torus knot round the sphere, a hue for every point.
        var knot: [Vector3] = [], colors: [Color] = []
        let steps = 360
        for k in 0 ..< steps {
            let t = Double(k) / Double(steps) * .tau
            let r = 1.15 + 0.32 * cos(3 * t)
            knot.append(Vector3(r * cos(2 * t), 0.9 + 0.5 * sin(3 * t), r * sin(2 * t)))
            colors.append(Color(hue: Double(k) / Double(steps), saturation: 0.65, brightness: 1))
        }
        strokeWeight(3)
        strokeJoin(.round)
        drawPolyline(knot, colors: colors, closed: true)

        stroke(.white)
        strokeCap(.round)
        drawLine(Vector3(-3.6, 1.0, -1.6), Vector3(3.6, 1.0, -1.6))

        stroke(Color(hex: 0xF2B544))
        strokeWeight(5)
        drawLine(Vector3(-2.6, 0.01, 2.2), Vector3(-2.2, 0.01, -6))
        strokeWeight(0.09, in: .world)
        drawLine(Vector3(2.6, 0.01, 2.2), Vector3(2.2, 0.01, -6))
    }
}
