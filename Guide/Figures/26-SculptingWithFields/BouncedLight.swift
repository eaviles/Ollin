// figure: frame=0
//
// Guide figure (Chapter 26): global illumination. A Cornell-style room whose only
// light is one spot pool on the floor: everything else the picture shows, the lit
// ceiling, the dyed statue, the filled shadows, is that pool re-delivered by the
// walls. The colored walls exist to be seen again on the white things between them.
import Ollin

final class BouncedLight: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    override func draw() {
        background(.black)
        camera(.perspective(eye: Vector3(0, 2.1, 9.4), target: Vector3(0, 1.9, 0),
                            fieldOfView: .pi / 3.4))
        toneMap(.aces, exposure: 1.35)
        spotLight(.white, at: Vector3(0.5, 3.8, 0.9), direction: Vector3(0.05, -1, -0.02),
                  coneAngle: .pi / 3.2, penumbra: 0.5, intensity: 3.4)
        castShadows()
        globalIllumination(intensity: 1.6)

        // The room: white floor, ceiling, and back; an orange and a teal wall.
        withState { fill(Color(white: 0.88)); translate(0, -0.1, 0); drawBox(width: 8.4, height: 0.2, depth: 8.4) }
        withState { fill(Color(white: 0.88)); translate(0, 4.1, 0); drawBox(width: 8.4, height: 0.2, depth: 8.4) }
        withState { fill(Color(white: 0.88)); translate(0, 2, -4.3); drawBox(width: 8.4, height: 4.4, depth: 0.2) }
        withState { fill(Color(hex: 0xd4622a)); translate(-4.3, 2, 0); drawBox(width: 0.2, height: 4.4, depth: 8.4) }
        withState { fill(Color(hex: 0x2a9d9d)); translate(4.3, 2, 0); drawBox(width: 0.2, height: 4.4, depth: 8.4) }

        // White things between the colored walls, there to be dyed.
        withState {
            fill(Color(white: 0.9))
            translate(-1.9, 1.1, -0.4); rotateY(0.42)
            drawBox(width: 1.5, height: 2.2, depth: 1.5)
        }
        withState { fill(Color(white: 0.9)); translate(1.7, 0.85, 0.2); drawSphere(radius: 0.85) }
    }
}
