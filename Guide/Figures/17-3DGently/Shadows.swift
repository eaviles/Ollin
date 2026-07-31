// figure: frame=0
//
// Guide figure (Chapter 17): what a cast shadow tells you. Four identical
// spheres at increasing heights over one floor. The shadow is crisp where a
// sphere touches down and spreads as the gap grows, which is the whole reason
// the eye reads height from it.
import Ollin

final class Shadows: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ball = Mesh.icosphere(radius: 0.5, subdivisions: 3)
    let floor = Mesh.plane(width: 14, depth: 8)

    override func draw() {
        background(Color(hex: 0x141821))
        camera(.perspective(eye: Vector3(0, 4.4, 9.2), target: Vector3(0, 1.5, 0),
                            fieldOfView: .pi / 4.2))

        // Nearly overhead, so each shadow sits out in the open next to its
        // sphere instead of hiding behind it.
        directionalLight(.white, direction: Vector3(-0.22, -1, -0.16), intensity: 1.3)
        ambientLight(Color(white: 0.17))
        castShadows()
        shadowSoftness(1)

        fill(Color(hex: 0x8A94A6))
        material(.matte)
        withState { translate(0, -0.02, 0); drawMesh(floor) }

        let heights = [0.0, 1.0, 2.1, 3.4]
        for (index, lift) in heights.enumerated() {
            withState {
                translate(Double(index) * 2.3 - 3.45, 0.5 + lift, 0)
                fill(Color(hex: 0xE2643C))
                material(.plastic)
                drawMesh(ball)
            }
        }
    }
}
