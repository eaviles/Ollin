import Ollin
import Foundation

// Self-shadowing in the raymarched 3D SDF fields. With `castShadows()`, a marched field
// shadows itself: a soft penumbra march toward the casting light, evaluated as part of the
// surface shading. Here a slab and the shapes standing on it are one merged field (a union
// block), so the shapes drop soft shadows onto the slab and onto one another. The field
// self-shadows but does not yet cast into the mesh shadow maps, so this is one field.
@main
final class RaymarchedShadow: Sketch {
    override func draw() {
        background(Color(hex: 0x0c0f14))
        let t = time

        camera(.orbiting(target: Vector3(0, -0.2, 0), radius: 8.0,
                         azimuth: t * 0.25, elevation: 0.32,
                         fieldOfView: .pi / 4, near: 0.1, far: 40))

        // A key from the upper left (travels down-right) so the shapes throw their shadows
        // across the slab.
        directionalLight(.white, direction: Vector3(0.7, -0.95, -0.35),
                         intensity: 1.25, softness: 0.2)
        ambientLight(Color(white: 0.13))
        castShadows()
        material(.glossy)

        // One field: a ground slab unioned with three shapes standing on it. The union
        // block captures the bare primitives as fields, so the whole thing self-shadows.
        union {
            fill(Color(hex: 0x6b7280))
            withState { translate(0, -0.95, 0); drawBox(width: 7, height: 0.4, depth: 7) }

            fill(Color(hex: 0x38bdf8))
            withState { translate(-1.7, -0.05, 0.2); drawSphere(radius: 0.7) }
            fill(Color(hex: 0xf472b6))
            withState { translate(0.4, 0.15, -0.6); rotateZ(0.25); drawCapsule(radius: 0.34, height: 1.2) }
            fill(Color(hex: 0xfacc15))
            withState { translate(1.8, -0.05, 0.7); drawCone(radius: 0.6, height: 1.5) }
        }
    }
}
