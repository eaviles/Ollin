import Ollin
import Foundation

// Per-axis sizing of a raymarched 3D SDF field. `stretched` inserts straight space along an axis
// (a sphere becomes a capsule) and stays an exact distance field, so a smooth union blends evenly.
// `scaled(x:y:z:)` is a true non-uniform scale (a sphere becomes an ellipsoid), but only a
// conservative bound, which is why `stretched` is the preferred per-axis tool. Left: two stretched
// spheres smooth-union into a clean cross; right: a sphere scaled into an ellipsoid.
@main
final class RaymarchedStretch: Sketch {
    override func draw() {
        background(Color(hex: 0x0d1018))
        let t = time
        camera(.orbiting(target: Vector3(0, 0, 0), radius: 8.5, azimuth: t * 0.3, elevation: 0.3,
                         fieldOfView: .pi / 4, near: 0.1, far: 50))
        directionalLight(.white, direction: Vector3(-0.3, -0.8, -0.5), intensity: 1.2, softness: 0.3)
        ambientLight(Color(white: 0.2))
        material(.glossy)

        // Stretch: a vertical and a horizontal capsule (spheres elongated along y and x) smooth-
        // union into a clean cross — the exact SDF keeps the blend fillet even.
        let cross = SDF3D.sphere(radius: 0.55).stretched(y: 1.0).colored(Color(hex: 0x67c1ff))
            .smoothUnion(SDF3D.sphere(radius: 0.55).stretched(x: 1.0).colored(Color(hex: 0xff7ab0)), k: 0.5)
        withState { translate(-2.4, 0, 0); rotateY(t * 0.25); drawSDF3D(cross) }

        // Non-uniform scale: a sphere squashed into an ellipsoid (a conservative distance bound).
        let ellipsoid = SDF3D.sphere(radius: 1.0).scaled(x: 1.5, y: 0.6, z: 1.0)
            .colored(Color(hex: 0xffd166))
        withState { translate(2.4, 0, 0); rotateZ(t * 0.3); drawSDF3D(ellipsoid) }
    }
}
