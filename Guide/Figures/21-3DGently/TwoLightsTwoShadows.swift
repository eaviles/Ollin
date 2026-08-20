// figure: frame=0
//
// Guide figure (Chapter 21): a frame casts from more than one light. One box
// over one floor, lit by a warm key on the left and a cool key on the right,
// so it drops two shadows that fan apart and cross where they overlap. The
// dim overhead fill is told not to cast, which is the counter-example.
import Ollin

final class TwoLightsTwoShadows: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let block = Mesh.box(width: 1.5, height: 1.5, depth: 1.5)
    let floor = Mesh.plane(width: 13, depth: 8)

    override func draw() {
        background(Color(hex: 0x141821))
        camera(.perspective(eye: Vector3(0, 3.6, 6.4), target: Vector3(0, 0.75, 0),
                            fieldOfView: .pi / 4.2))

        // Two keys, one from each side, so their shadows fan apart.
        directionalLight(Color(hex: 0xFFD9A8), direction: Vector3(0.62, -0.72, -0.30),
                         intensity: 1.15)
        directionalLight(Color(hex: 0xA8CCFF), direction: Vector3(-0.62, -0.72, -0.30),
                         intensity: 1.15)
        // A fill that lifts the shaded faces and throws nothing.
        directionalLight(Color(white: 0.7), direction: Vector3(0, -1, 0.5), intensity: 0.25,
                         castsShadow: false)
        ambientLight(Color(white: 0.14))
        castShadows()
        shadowSoftness(0.5)

        fill(Color(hex: 0x8A94A6))
        material(.matte)
        withState { translate(0, -0.02, 0); drawMesh(floor) }

        fill(Color(hex: 0xE2643C))
        material(.plastic)
        withState { translate(0, 0.75, 0); rotateY(0.35); drawMesh(block) }
    }
}
