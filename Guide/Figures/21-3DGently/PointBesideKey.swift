// figure: frame=0 probe
//
// Guide figure (Chapter 21): a point light casts from any slot. A cool key from
// the right throws each block's shadow to the left, and a warm lamp standing to
// the left throws its own of each to the right, so the pairs fan apart.
// Marked as a probe: it is the sample's witness for a point caster beside a
// map caster, which is a route no other figure takes.
import Ollin

final class PointBesideKey: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let block = Mesh.box(width: 1.3, height: 1.9, depth: 1.3)
    let post = Mesh.cylinder(radius: 0.42, height: 2.4)
    let floor = Mesh.plane(width: 20, depth: 14)

    override func draw() {
        background(Color(hex: 0x141821))
        camera(.perspective(eye: Vector3(-0.6, 4.4, 7.2), target: Vector3(0.4, 0.8, 0),
                            fieldOfView: .pi / 4.2))

        // The key, cool and from the right: its shadows reach left.
        directionalLight(Color(hex: 0xC9DBFF), direction: Vector3(-0.62, -0.78, -0.20),
                         intensity: 0.95)
        // The lamp, warm and standing to the left: its shadows reach right.
        pointLight(Color(hex: 0xFFC079), at: Vector3(-4.6, 3.2, 2.2), intensity: 1.5)
        // A fill that lifts the shaded faces and throws nothing.
        directionalLight(Color(white: 0.75), direction: Vector3(0, -0.5, -1),
                         intensity: 0.22, castsShadow: false)
        ambientLight(Color(white: 0.13))
        castShadows()
        shadowSoftness(0.45)

        fill(Color(hex: 0x93A0B4))
        material(.matte)
        withState { translate(0, -0.02, 0); drawMesh(floor) }

        material(.plastic)
        fill(Color(hex: 0xD8664A))
        withState { translate(-0.9, 0.95, 0.4); rotateY(0.3); drawMesh(block) }
        fill(Color(hex: 0x5FA9A0))
        withState { translate(1.9, 1.2, -0.6); drawMesh(post) }
    }
}
