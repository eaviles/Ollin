// figure: frame=0
//
// Guide figure (Chapter 18): the three kinds of light in one scene, each in
// its own color so its contribution is visible: a warm directional key, a
// cyan point light (marked by the small ball), and a magenta spot pooling
// on the floor.
import Ollin

final class LightKinds: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    override func draw() {
        background(Color(hex: 0x0B0D12))
        camera(.orbiting(target: Vector3(0, 0.5, 0), radius: 10.5,
                         azimuth: 0.25, elevation: 0.3, fieldOfView: .pi / 4.2))

        ambientLight(Color(white: 0.1))
        directionalLight(Color(hex: 0xFFD9A8), direction: Vector3(-0.6, -1, -0.35),
                         intensity: 0.7)
        pointLight(Color(hex: 0x39D8E8), at: Vector3(2.7, 1.7, 1.9), intensity: 0.9)
        spotLight(Color(hex: 0xE85FD0), at: Vector3(-3.4, 4.6, 2.6),
                  direction: Vector3(0, -1, 0), angle: .pi / 5, penumbra: 0.4,
                  intensity: 1.2)
        castShadows()

        fill(Color(white: 0.8))
        drawPlane(width: 26, depth: 26)

        withState {
            translate(-2.4, 0.85, 0.2)
            fill(Color(white: 0.9)); specular(0.5); shininess(80)
            drawSphere(radius: 0.85)
        }
        withState {
            translate(0.2, 0.75, -0.4); rotateY(0.5)
            fill(Color(white: 0.85)); specular(0.3); shininess(40)
            drawBox(size: 1.5)
        }
        withState {
            translate(2.5, 0.7, 0.6); rotateX(1.1); rotateY(0.4)
            fill(Color(white: 0.9)); specular(0.5); shininess(80)
            drawTorus(radius: 0.62, tube: 0.26)
        }

        // The point light's position, marked with a small self-lit ball.
        withState {
            translate(2.7, 1.7, 1.9)
            matcap(Matcap.shaded(baseColor: Color(hex: 0x39D8E8)))
            drawSphere(radius: 0.1)
        }

        fill(.white); textSize(26)
        withBillboard(at: Vector3(-4.4, 3.6, 0)) {
            textAlign(.left, .middle)
            drawText("directional: parallel rays, like the sun", 0, 0)
        }
        withBillboard(at: Vector3(2.7, 2.5, 1.9)) {
            textAlign(.center, .middle)
            drawText("point: a bulb at a position", 0, 0)
        }
        withBillboard(at: Vector3(-2.2, 0.6, 3.7)) {
            textAlign(.left, .middle)
            drawText("spot: a cone, aimed", 0, 0)
        }
    }
}
