import Ollin
import Foundation

// A raymarched 3D SDF field *receiving* a rasterized mesh's cast shadow. The field self-shadows
// analytically, and under a directional or spot light it also samples the shadow map, so a mesh's
// shadow lands on the field surface just as it would on another mesh. Here a floating mesh sphere
// drops a round shadow onto a wide SDF slab, beside the slab's own self-shadowed bumps.
@main
final class RaymarchedReceiveShadow: Sketch {
    override func draw() {
        background(Color(hex: 0x0c0f16))
        let t = time

        camera(.orbiting(target: Vector3(0, -0.2, 0), radius: 7.0,
                         azimuth: t * 0.25, elevation: 0.5,
                         fieldOfView: .pi / 4, near: 0.1, far: 50))

        directionalLight(.white, direction: Vector3(0.3, -0.95, -0.1),
                         intensity: 1.3, softness: 0.2)
        ambientLight(Color(white: 0.16))
        castShadows()
        material(.glossy)

        // The receiver: a wide SDF slab with two raised bumps (so it self-shadows too), its top
        // facing the light. The mesh sphere's shadow lands on it through the 2D shadow map.
        let slab = SDF3D.roundBox(width: 5.0, height: 0.6, depth: 4.0, radius: 0.25)
            .smoothUnion(SDF3D.sphere(radius: 0.7).at(x: -1.3, y: 0.4, z: 0.6), k: 0.5)
            .smoothUnion(SDF3D.sphere(radius: 0.55).at(x: 1.4, y: 0.35, z: -0.7), k: 0.5)
            .colored(Color(hex: 0x6aa9ff))
        withState { translate(0, -1.0, 0); drawSDF3D(slab) }

        // The caster: a mesh sphere floating above the slab, circling so its round shadow tracks
        // across the field surface.
        fill(Color(hex: 0xf472b6))
        withState { translate(cos(t * 0.6) * 1.3, 1.15, sin(t * 0.6) * 1.0); drawSphere(radius: 0.65) }
    }
}
