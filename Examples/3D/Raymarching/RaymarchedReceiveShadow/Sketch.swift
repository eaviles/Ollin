import Ollin
import Foundation

// A raymarched 3D SDF field *receiving* a rasterized mesh's cast shadow, under either kind
// of caster (press any key to switch). The field self-shadows analytically, and under a
// directional light it also samples the 2D shadow map, so a mesh's shadow lands on the
// field surface just as it would on another mesh. A point caster instead leaves its
// occluders in the omnidirectional cube (or, on a ray-tracing GPU, the acceleration
// structure), and the field samples whichever the same way a mesh receiver does. Here a
// floating mesh sphere circles over a wide SDF slab, dropping a round shadow that tracks
// across the field surface, beside the slab's own self-shadowed bumps.
@main
final class RaymarchedReceiveShadow: Sketch {

    /// Press any key to swap the caster kind.
    var usesPointLight = false

    override func draw() {
        background(Color(hex: 0x0c0f16))
        let t = time

        cameraShowcase(.turntable(period: .tau / 0.25), target: Vector3(0, -0.2, 0), radius: 7.0,
                    elevation: 0.5, fieldOfView: .pi / 4, near: 0.1, far: 50)

        if usesPointLight {
            pointLight(.white, at: Vector3(0, 4.5, 0.5), intensity: 2.0, specular: .white)
        } else {
            directionalLight(.white, direction: Vector3(0.3, -0.95, -0.1),
                             intensity: 1.3, softness: 0.2)
        }
        ambientLight(Color(white: 0.16))
        castShadows()
        material(.glossy)

        // The receiver: a wide SDF slab with two raised bumps (so it self-shadows too), its
        // top facing the light. The mesh sphere's shadow lands on it through whichever
        // record the caster wrote: the 2D map, the cube, or the acceleration structure.
        let slab = SDF3D.roundBox(width: 5.0, height: 0.6, depth: 4.0, radius: 0.25)
            .smoothUnion(SDF3D.sphere(radius: 0.7).at(-1.3, 0.4, 0.6), k: 0.5)
            .smoothUnion(SDF3D.sphere(radius: 0.55).at(1.4, 0.35, -0.7), k: 0.5)
            .colored(Color(hex: 0x6aa9ff))
        withState { translate(0, -1.0, 0); drawSDF3D(slab) }

        // The caster: a mesh sphere floating above the slab (a step lower under the bulb,
        // so it stays between the light and the field), circling so its round shadow
        // tracks across the field surface.
        fill(Color(hex: 0xf472b6))
        let orbitHeight = usesPointLight ? 1.0 : 1.15
        withState { translate(cos(t * 0.6) * 1.3, orbitHeight, sin(t * 0.6) * 1.0); drawSphere(radius: 0.65) }
    }

    override func keyPressed() { usesPointLight.toggle() }
}
