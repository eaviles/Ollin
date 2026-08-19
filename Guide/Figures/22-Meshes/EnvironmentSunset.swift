// figure: frame=0
//
// Guide figure (Chapter 22): the EnvironmentSky scene with `.sky(...)` swapped
// for a bundled photographic HDRI of a sunset. Same camera, same solids, same
// material; only the surroundings differ, which is the whole point of the pair.
import Ollin

final class EnvironmentSunset: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    override func draw() {
        camera(.perspective(eye: Vector3(2.2, 1.9, 5.2), target: Vector3(0, 1.0, 0),
                            fieldOfView: .pi / 4.4))
        environment(.sunset.backgroundBlur(0.2))
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
