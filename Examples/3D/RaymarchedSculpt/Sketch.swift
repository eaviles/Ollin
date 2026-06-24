import Ollin
import Foundation

// The scoped block form of the 3D SDF combinators: inside `smoothUnion(k:) { … }` the bare
// mesh primitives (`drawSphere`, `drawCapsule`, `drawCone`, …) are captured as fields and
// melted into one sphere-traced surface instead of drawn as separate solids. Each call's
// own `fill` becomes that lobe's color, so they blend across the seams. The transform stack
// works inside the block (a primitive drawn under `translate`/`rotate` lands there in the
// merged field), so this is a little blob creature posed with `withState`.
@main
final class RaymarchedSculpt: Sketch {
    override func draw() {
        background(Color(hex: 0x101418))
        let t = time

        camera(.orbiting(target: Vector3(0, 0.2, 0), radius: 6.0,
                         azimuth: t * 0.4, elevation: 0.25,
                         fieldOfView: .pi / 4, near: 0.1, far: 40))

        directionalLight(.white, direction: Vector3(-0.5, 0.8, 0.4),
                         intensity: 1.2, softness: 0.3)
        ambientLight(Color(white: 0.18))
        material(.jade)

        let wobble = sin(t * 2) * 0.12

        // Everything inside melts together: body + head + two arms + a hat, each posed with
        // the transform stack, each its own color blending at the smooth-union seams.
        smoothUnion(k: 0.35) {
            fill(Color(hex: 0x3ad6c5))
            withState { translate(0, -0.6, 0); drawSphere(radius: 0.95) }   // body
            withState { translate(0, 0.7, 0); drawSphere(radius: 0.62) }    // head

            fill(Color(hex: 0xffb84d))
            withState {
                translate(-0.9, -0.4, 0); rotateZ(0.6 + wobble)
                drawCapsule(radius: 0.16, height: 0.7)                      // left arm
            }
            withState {
                translate(0.9, -0.4, 0); rotateZ(-0.6 - wobble)
                drawCapsule(radius: 0.16, height: 0.7)                      // right arm
            }

            fill(Color(hex: 0xff5d73))
            withState { translate(0, 1.5, 0); drawCone(radius: 0.45, height: 0.7) }  // hat
        }
    }
}
