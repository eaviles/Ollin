// figure: frame=0
//
// Guide figure (Chapter 33): the frame through the camera's lens. A row of
// balls on a waxed floor runs away from the camera, focused on the middle one.
// The nearest is a soft veil over the floor, the farther ones soften, and the
// small lamps strung along the back wall open into six-sided discs, the shape
// of the six-bladed iris the lamplit room's camera carries.
import Ollin

final class ThroughTheLens: Sketch {
    override var canvasSize: CanvasSize { .size(880, 420) }

    override func draw() {
        background(Color(hex: 0x120E0C))
        var lens = Camera3D.perspective(eye: Vector3(-1.6, 0.75, 4.6), target: Vector3(0.2, 0.35, 0),
                                        fieldOfView: .pi / 4.6)
        lens.aperture = 0.14
        lens.apertureBlades = 6
        camera(lens)
        depthOfField(maxBlur: 40)
        directionalLight(Color(hex: 0xFFE6C8), direction: Vector3(0.6, -0.7, -0.4), intensity: 1.7)
        ambientLight(Color(hex: 0x3A2A22))

        // The waxed floor, in boards running away from the camera.
        for z in -12 ..< 6 {
            for x in -6 ..< 6 {
                let shade = 0.32 + 0.08 * Double((x * 7 + z * 3) & 3)
                fill(Color(red: shade * 1.25, green: shade * 0.8, blue: shade * 0.55))
                withState { translate(Double(x) + 0.5, -0.03, Double(z) + 0.5); drawBox(width: 0.98, height: 0.06, depth: 0.98) }
            }
        }

        let balls: [(x: Double, z: Double, hex: UInt32)] =
            [(-1.73, 2.54, 0x2F7F86), (-1.05, 1.3, 0xC9A23A), (0.2, 0, 0xB8452E), (2.69, -1.77, 0x5E8F4E), (5.2, -4.4, 0x7A5AA8)]
        specular(0.45); specularSharpness(50)
        for b in balls {
            fill(Color(hex: b.hex))
            withState { translate(b.x, 0.35, b.z); drawSphere(radius: 0.35, segments: 64, rings: 32) }
        }

        withoutLights {
            for i in 0 ..< 15 {
                fill(Color(hex: 0xFFC27A))
                withState {
                    translate(-5 + Double(i) * 0.9, 1.9 + 0.12 * sin(Double(i) * 1.7), -10)
                    drawMesh(Mesh.sphere(radius: 0.05).glowing(24))
                }
            }
        }
    }
}
