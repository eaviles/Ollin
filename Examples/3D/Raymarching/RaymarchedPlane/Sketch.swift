import Ollin
import Foundation

// An infinite plane primitive for the raymarched 3D SDF fields. A plane has no finite bounds,
// so its field marches to the camera's far plane instead of a box. Merged with the scene's
// shapes as one field under `castShadows()`, it becomes a ground the shapes drop soft
// self-shadows onto: the whole composition is one sphere-traced surface, so the shadows fall
// analytically with no shadow map.
@main
final class RaymarchedPlane: Sketch {
    override func draw() {
        background(Color(hex: 0x0a0e16))

        cameraShowcase(.turntable(period: .tau / 0.22), target: Vector3(0, 0.1, 0), radius: 7,
                    elevation: 0.32, fieldOfView: .pi / 4, near: 0.1, far: 60)

        directionalLight(.white, direction: Vector3(0.4, -0.92, -0.25),
                         intensity: 1.3, softness: 0.2)
        ambientLight(Color(white: 0.14))
        castShadows()
        material(.glossy)

        // An infinite floor at y = -0.85 merged with three shapes as one field, so each shape
        // casts a soft self-shadow onto the plane (and onto its neighbors).
        let floor = SDF3D.plane(offset: -0.85).colored(Color(hex: 0x5b6472))
        let ball = SDF3D.sphere(radius: 0.7).colored(Color(hex: 0x38bdf8))
            .at(-1.5, -0.15, 0.2)
        let bar = SDF3D.capsule(radius: 0.3, height: 1.0).colored(Color(hex: 0xf472b6))
            .rotatedZ(0.5).at(0.3, 0.05, -0.7)
        let pin = SDF3D.cone(radius: 0.55, height: 1.6).colored(Color(hex: 0xfacc15))
            .at(1.7, -0.05, 0.6)

        drawSDF3D(floor.union(ball).union(bar).union(pin))
    }
}
