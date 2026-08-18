// figure: frame=0 unstable
//
// Guide figure (Chapter 18): caustics. A clear glass sphere throws a tight
// bright spot inside its own shadow, a bottle-green sphere throws a green
// one, and a chrome ring lying almost flat folds light into a curved fan.
// Ray-traced; the camera looks down enough to keep the floor in view, since
// the floor is where the light patterns land.
import Ollin

final class CausticLight: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    override func draw() {
        background(Color(hex: 0x101318))
        environment(.studio.intensity(0.55).backgroundBlur(0.6))
        directionalLight(.white, direction: Vector3(-0.35, -1, -0.2), intensity: 2.2)
        castShadows()
        rayTracedReflections()
        caustics()
        camera(.orbiting(target: Vector3(0, 0.3, 0.8), radius: 9.2, azimuth: 0.08,
                         elevation: 0.58, fieldOfView: .pi / 4, near: 1, far: 40))

        // A matte floor: the screen the light patterns land on.
        withState {
            material(.dielectric(roughness: 0.85))
            fill(Color(hex: 0x878c99))
            translate(0, -0.5, 0)
            drawBox(width: 26, height: 1.0, depth: 16)
        }

        // A clear solid sphere, hovering so its focal point lands on the floor.
        withState {
            material(.glass(thickness: 2.4))
            fill(.white)
            translate(-2.4, 1.7, 0)
            drawSphere(radius: 1.2)
        }

        // The same lens in bottle green: its spot is colored by the crossing.
        withState {
            material(.glass(thickness: 2.0,
                            attenuationColor: Color(hex: 0x2e8f5b),
                            attenuationDistance: 1.6))
            fill(.white)
            translate(2.5, 1.15, -0.4)
            drawSphere(radius: 1.0)
        }

        // A chrome ring lying almost flat: its inner wall folds the fan.
        withState {
            material(.metal(roughness: 0.06))
            fill(Color(hex: 0xf2f4f8))
            translate(0.3, 0.3, 2.6)
            rotateX(0.16)
            drawTorus(radius: 1.15, tube: 0.16)
        }
    }
}
