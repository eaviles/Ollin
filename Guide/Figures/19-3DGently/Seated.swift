// figure: frame=0
//
// Guide figure (Chapter 19): the seam contact shadows restore. A still life
// under a deliberately wide soft shadow: the map alone leaves every base a
// little loose, and the short screen-space march draws the dark line that
// seats each resting solid. The hovering sphere is the control; no contact,
// so no seam forms under it.
import Ollin

final class Seated: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    override func draw() {
        background(Color(hex: 0x141821))
        camera(.perspective(eye: Vector3(2.6, 3.4, 9.0), target: Vector3(0, 0.7, 0),
                            fieldOfView: .pi / 4.2))

        directionalLight(.white, direction: Vector3(-0.7, -0.55, -0.3), intensity: 1.15)
        ambientLight(Color(white: 0.2))
        castShadows()
        shadowSoftness(0.9)
        contactShadows()

        fill(Color(hex: 0x8A94A6))
        material(.matte)
        withState { translate(0, -0.02, 0); drawMesh(Mesh.plane(width: 16, depth: 10)) }

        material(.plastic)
        withState {
            fill(Color(hex: 0xE2643C))
            translate(-1.9, 0.7, -0.3)
            drawBox(width: 1.4, height: 1.4, depth: 1.4)
        }
        withState {
            fill(Color(hex: 0x4E8FB0))
            translate(0.5, 0.62, 1.1)
            drawSphere(radius: 0.62)
        }
        withState {
            fill(Color(hex: 0xD9A441))
            translate(2.0, 0.55, -0.9)
            drawCylinder(radius: 0.55, height: 1.1)
        }
        // The control: really hovering, so no seam should form beneath it (its
        // soft shadow drifts off to the left, well clear of the box top).
        withState {
            fill(Color(white: 0.82))
            translate(-3.3, 2.2, 1.5)
            drawSphere(radius: 0.4)
        }
    }
}
