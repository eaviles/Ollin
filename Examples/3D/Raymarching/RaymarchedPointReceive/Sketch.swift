import Ollin
import Foundation

// A raymarched 3D SDF field *receiving* a rasterized mesh's cast shadow under a *point* light. A
// directional or spot caster renders its occluders into the 2D shadow map; a point caster instead
// leaves them in the omnidirectional cube (or, on a ray-tracing GPU, the acceleration structure),
// and the field samples whichever the same way a mesh receiver does. Here a mesh sphere circles
// beneath an overhead bulb, dropping a soft round shadow that tracks across a wide SDF slab, beside
// the slab's own self-shadowed bumps.
@main
final class RaymarchedPointReceive: Sketch {
    override func draw() {
        background(Color(hex: 0x0b0d14))
        let t = time

        cameraShowcase(.turntable(period: .tau / 0.25), target: Vector3(0, -0.2, 0), radius: 7.0,
                    elevation: 0.5, fieldOfView: .pi / 4, near: 0.1, far: 50)

        pointLight(.white, at: Vector3(0, 4.5, 0.5), intensity: 2.0, specular: .white)
        ambientLight(Color(white: 0.16))
        castShadows()
        material(.glossy)

        // The receiver: a wide SDF slab with two raised bumps (so it self-shadows too), its top
        // facing the bulb. The mesh sphere's shadow lands on it through the point caster's map.
        let slab = SDF3D.roundBox(width: 5.0, height: 0.6, depth: 4.0, radius: 0.25)
            .smoothUnion(SDF3D.sphere(radius: 0.7).at(-1.3, 0.4, 0.6), k: 0.5)
            .smoothUnion(SDF3D.sphere(radius: 0.55).at(1.4, 0.35, -0.7), k: 0.5)
            .colored(Color(hex: 0x6aa9ff))
        withState { translate(0, -1.0, 0); drawSDF3D(slab) }

        // The caster: a mesh sphere circling between the bulb and the slab, so its round shadow
        // sweeps across the field surface.
        fill(Color(hex: 0xf472b6))
        withState { translate(cos(t * 0.6) * 1.3, 1.0, sin(t * 0.6) * 1.0); drawSphere(radius: 0.65) }
    }
}
