import Ollin
import Foundation

// A raymarched 3D SDF field casting a shadow onto a rasterized mesh. The field self-shadows
// analytically, but here it also renders into the directional/spot shadow map, so meshes receive
// its cast shadow just as they do another mesh's. The mesh floor (and the mesh sphere on the
// right, for comparison) catch the soft shadow of the floating field blob on the left.
@main
final class RaymarchedCastShadow: Sketch {
    override func draw() {
        background(Color(hex: 0x0c0f16))
        let t = time

        cameraShowcase(.turntable(period: .tau / 0.25), target: .zero, radius: 7.5,
                    elevation: 0.4, fieldOfView: .pi / 4, near: 0.1, far: 50)

        directionalLight(.white, direction: Vector3(0.35, -0.92, -0.2),
                         intensity: 1.3, softness: 0.2)
        ambientLight(Color(white: 0.16))
        castShadows()
        material(.glossy)

        // Rasterized meshes: the floor (the receiver) and a sphere whose own cast shadow is the
        // reference the field's should match.
        fill(Color(hex: 0x5b6472))
        withState { translate(0, -1.1, 0); drawBox(width: 9, height: 0.4, depth: 9) }
        fill(Color(hex: 0xf472b6))
        withState { translate(2.1, -0.3, 0); drawSphere(radius: 0.6) }

        // A raymarched SDF blob floating above the floor: it drops a soft shadow onto the mesh
        // floor through the field-into-shadow-map pass, the same way the mesh sphere does.
        let blob = SDF3D.sphere(radius: 0.7)
            .smoothUnion(SDF3D.sphere(radius: 0.5).at(0.85, 0.35, 0.2), k: 0.45)
            .smoothUnion(SDF3D.sphere(radius: 0.5).at(-0.2, 0.5, -0.4), k: 0.45)
            .colored(Color(hex: 0x38bdf8))
        withState { translate(-1.8, 0.1, 0); rotateY(t * 0.4); drawSDF3D(blob) }
    }
}
