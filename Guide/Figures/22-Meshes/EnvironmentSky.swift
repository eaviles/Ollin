// figure: frame=0
//
// Guide figure (Chapter 22): the same glossy cluster under the procedural sky.
// Pairs with EnvironmentSunset, which is this sketch with one word changed, so
// the two images isolate exactly what an environment contributes.
import Ollin

final class EnvironmentSky: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    override func draw() {
        camera(.perspective(eye: Vector3(2.2, 1.9, 5.2), target: Vector3(0, 1.0, 0),
                            fieldOfView: .pi / 4.4))
        environment(.sky(sunElevation: 0.35).backgroundBlur(0.25))
        toneMap(.aces, exposure: 1.0)

        material(.matte)
        fill(Color(hex: 0x7A8290))
        drawPlane(width: 40, depth: 40)

        material(.metal(roughness: 0.12))
        fill(Color(hex: 0xD8DCE2))
        withState { translate(0, 0.8, 0); drawSphere(radius: 0.72) }
        withState {
            translate(0.66, 0.46, 0.2)
            scale(1, 0.68, 1)
            drawSphere(radius: 0.5)
        }
        withState { translate(-0.34, 1.42, 0.16); drawSphere(radius: 0.38) }
    }
}
