import Ollin
import Foundation

// A raymarched 3D SDF field casting a shadow onto a rasterized mesh under a POINT light. A
// directional or spot field-cast goes through the 2D shadow map, but a point light has no such
// map, so the lit mesh fragments march the field inline toward the light instead. Here a floating
// SDF blob (and a mesh sphere, for comparison) drop their shadows onto the floor from a point bulb.
@main
final class RaymarchedPointCast: Sketch {
    override func draw() {
        background(Color(hex: 0x0A0B10))
        let t = time

        cameraShowcase(.turntable(period: .tau / 0.2), target: Vector3(0, 0.8, 0), radius: 11,
                    elevation: 0.5, fieldOfView: .pi / 4.6)

        ambientLight(Color(white: 0.1))
        let bulb = Vector3(0, 5.5, 0)
        pointLight(.white, at: bulb, intensity: 1.8, specular: .white)
        castShadows()
        material(.glossy)

        // The receiver floor.
        withState { fill(Color(white: 0.8)); specular(0.05); translate(0, -0.5, 0); drawPlane(width: 24, depth: 24) }

        // A mesh sphere whose own point-light shadow is the reference the field's should match.
        withState { fill(Color(hex: 0xf472b6)); translate(2.2, 1.4, 0); drawSphere(radius: 0.8) }

        // The raymarched SDF blob: it drops a soft shadow onto the floor through the mesh
        // fragments' inline field march (the point-light cast path).
        let blob = SDF3D.sphere(radius: 0.8)
            .smoothUnion(SDF3D.sphere(radius: 0.6).at(0.9, 0.3, 0.2), k: 0.5)
            .smoothUnion(SDF3D.sphere(radius: 0.55).at(-0.3, 0.5, -0.4), k: 0.5)
            .colored(Color(hex: 0x38bdf8))
        withState { translate(-2.0, 1.5, 0); rotateY(t * 0.4); drawSDF3D(blob) }

        drawCaption("Raymarched SDF field casting onto a mesh under a point light")
    }
}
