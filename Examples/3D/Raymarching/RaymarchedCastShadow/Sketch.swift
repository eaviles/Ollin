import Ollin
import Foundation

// A raymarched 3D SDF field casting a shadow onto a rasterized mesh, under either kind of
// caster (press any key to switch). The field self-shadows analytically, but under the
// directional light it also renders into the 2D shadow map, so meshes receive its cast
// shadow just as they do another mesh's. A point light has no such map, so the lit mesh
// fragments march the field inline toward the light instead. Either way the mesh floor
// (and the mesh sphere on the right, for comparison) catch the soft shadow of the
// floating field blob on the left.
@main
final class RaymarchedCastShadow: Sketch {

    /// Press any key to swap the caster kind.
    var usesPointLight = false

    override func draw() {
        background(Color(hex: 0x0c0f16))
        let t = time

        if usesPointLight {
            // The point variant lifts the camera and steps it back, so the overhead
            // bulb's shadows read on the floor.
            cameraShowcase(.turntable(period: .tau / 0.2), target: Vector3(0, 0.8, 0), radius: 11,
                        elevation: 0.5, fieldOfView: .pi / 4.6)
            pointLight(.white, at: Vector3(0, 5.5, 0), intensity: 1.8, specular: .white)
        } else {
            cameraShowcase(.turntable(period: .tau / 0.25), target: .zero, radius: 7.5,
                        elevation: 0.4, fieldOfView: .pi / 4, near: 0.1, far: 50)
            directionalLight(.white, direction: Vector3(0.35, -0.92, -0.2),
                             intensity: 1.3, softness: 0.2)
        }
        ambientLight(Color(white: 0.16))
        castShadows()
        material(.glossy)

        // Rasterized meshes: the floor (the receiver) and a sphere whose own cast shadow is the
        // reference the field's should match.
        fill(Color(hex: 0x5b6472))
        withState { translate(0, -1.1, 0); drawBox(width: 9, height: 0.4, depth: 9) }
        fill(Color(hex: 0xf472b6))
        withState { translate(2.1, -0.3, 0); drawSphere(radius: 0.6) }

        // A raymarched SDF blob floating above the floor. Under the directional light it
        // drops its soft shadow onto the mesh floor through the field-into-shadow-map pass,
        // the same way the mesh sphere does; under the point light, through the mesh
        // fragments' inline field march (the point-light cast path).
        let blob = SDF3D.sphere(radius: 0.7)
            .smoothUnion(SDF3D.sphere(radius: 0.5).at(0.85, 0.35, 0.2), k: 0.45)
            .smoothUnion(SDF3D.sphere(radius: 0.5).at(-0.2, 0.5, -0.4), k: 0.45)
            .colored(Color(hex: 0x38bdf8))
        withState { translate(-1.8, 0.1, 0); rotateY(t * 0.4); drawSDF3D(blob) }

        drawCaption(usesPointLight
            ? "Field casting onto a mesh under a point light (any key: directional)"
            : "Field casting onto a mesh under a directional light (any key: point)")
    }

    override func keyPressed() { usesPointLight.toggle() }
}
