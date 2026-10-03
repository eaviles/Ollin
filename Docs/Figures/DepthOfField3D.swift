// figure: frame=0
//
// Figure for Docs/3D/3D.md (Depth of field): the 3D frame blurred by its own
// depth through the camera's lens. A row of balls running back along a tiled
// floor with the lens focused on the third; the near ball spreads into a veil
// over the floor, the far ones soften, and a string of small lights at the back
// opens into six-sided discs, the shape of a six-bladed iris.
import Ollin

final class DepthOfField3D: Sketch {
    override var canvasSize: CanvasSize { .size(880, 400) }

    override func draw() {
        background(Color(hex: 0x0B0C12))
        var lens = Camera3D.perspective(eye: Vector3(1.4, 1.1, 5.2), target: Vector3(0, 0.45, 0),
                                        fieldOfView: .pi / 5)
        lens.aperture = 0.16
        lens.apertureBlades = 6
        camera(lens)
        depthOfField(maxBlur: 40)
        directionalLight(.white, direction: Vector3(0.75, -0.55, -0.35), intensity: 1.8)
        ambientLight(Color(white: 0.25))

        for z in -14 ..< 5 {
            for x in -8 ..< 8 {
                fill(Color(white: (x + z) & 1 == 0 ? 0.62 : 0.22))
                withState { translate(Double(x) + 0.5, -0.02, Double(z) + 0.5); drawBox(width: 1, height: 0.04, depth: 1) }
            }
        }

        let balls: [(x: Double, z: Double, hex: UInt32)] =
            [(2.1, 2.7, 0x3D7BD9), (1.0, 1.3, 0xE0A23B), (-0.2, 0, 0xD9553D), (-1.6, -2.2, 0x58B368), (-3.2, -5, 0x9B6BD6)]
        specular(0.5); specularSharpness(60)
        for b in balls {
            fill(Color(hex: b.hex))
            withState { translate(b.x, 0.45, b.z); drawSphere(radius: 0.45, segments: 64, rings: 32) }
        }

        withoutLights {
            for i in 0 ..< 13 {
                fill(Color(hue: 0.08 + Double(i) * 0.012, saturation: 0.55, brightness: 1))
                withState {
                    translate(-6 + Double(i), 2.2 + 0.25 * sin(Double(i)), -13)
                    drawMesh(Mesh.sphere(radius: 0.06).glowing(20))
                }
            }
        }
    }
}
